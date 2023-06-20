#!/usr/bin/env bash
#set -e

# Export Vars
export PWDIR=$(pwd)
export KERNELDIR=$PWDIR/13
export ANYKERNELDIR=$PWDIR/Anykernel3
export KERNEL_DEFCONFIG=sweet-perf_defconfig
export BUILD_TIME=$(date +"%Y%m%d-%H%M%S")
export ARCH=arm64
export SUBARCH=arm64
export ZIPNAME=XYZABC
export BUILD_VARIANTS=(OSS MIUI)

export BUILD_TYPE=canary
export PRERELEASE=true
echo "Build Type: Canary"
if [ x${1} == xstable ]; then
    export BUILD_TYPE=stable
    export PRERELEASE=false
    echo "Build Type: Stable"
fi

# Clone kernel
echo -e "$green << cloning kernel >> \n $white"
git clone https://${GH_TOKEN}@github.com/DoraCore-Projects/android_kernel_xiaomi_sweet.git $KERNELDIR > /dev/null 2>&1
cd $KERNELDIR

# Cleanup
rm -rf $PWDIR/ZIPOUT
rm -rf $KERNELDIR/out

# Update Submodules
git submodule init
git submodule update
git submodule update --recursive --remote
git add -vAf
git commit -sm "Kernel: Latest commit, KernelSU and KProfiles"

export commit_sha=$(git rev-parse HEAD)
echo -e "Latest commit is: "${commit_sha}

sleep 5

mkdir -p $PWDIR/ZIPOUT

# Tool Chain
echo -e "$green << cloning gcc >> \n $white"
git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 "$PWDIR"/gcc64 > /dev/null 2>&1
git clone --depth=1 https://github.com/mvaisakh/gcc-arm "$PWDIR"/gcc32 > /dev/null 2>&1
export PATH="$PWDIR/gcc64/bin:$PWDIR/gcc32/bin:$PATH"
export KBUILD_COMPILER_STRING=$("$PWDIR"/gcc64/bin/aarch64-elf-gcc --version | head -n 1)

# Clang
echo -e "$green << cloning clang >> \n $white"
git clone -b 15 --depth=1 https://gitlab.com/PixelOS-Devices/playgroundtc.git "$PWDIR"/clang > /dev/null 2>&1
export PATH="$PWDIR/clang/bin:$PATH"
export KBUILD_COMPILER_STRING=$("$PWDIR"/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

# Speed up build process
MAKE="./makeparallel"
BUILD_START=$(date +"%s")
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

start_build() {
    echo "**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****"
    echo -e "$blue***********************************************"
    echo "          BUILDING KERNEL          "
    echo -e "***********************************************$nocol"
    make $KERNEL_DEFCONFIG O=out CC=clang
    make -j$(nproc --all) O=out CC=clang \
        ARCH=arm64 \
        LLVM=1 \
        LLVM_IAS=1 \
        AR=llvm-ar \
        NM=llvm-nm \
        LD=ld.lld \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee error.log

    find $KERNELDIR/out/arch/arm64/boot/dts/ -name '*.dtb' -exec cat {} + > $KERNELDIR/out/arch/arm64/boot/dtb

    # export IMGDTB=$KERNELDIR/out/arch/arm64/boot/Image.gz-dtb
    export IMG=$KERNELDIR/out/arch/arm64/boot/Image.gz
    export DTBO=$KERNELDIR/out/arch/arm64/boot/dtbo.img
    export DTB=$KERNELDIR/out/arch/arm64/boot/dtb

    if [ -f $IMG ] && [ -f $DTBO ] && [ -f $DTB ]; then
        echo "------ Finishing Build ------"
        git clone https://${GH_TOKEN}@github.com/DoraCore-Projects/Anykernel3.git $ANYKERNELDIR
        cp -r $IMG $ANYKERNELDIR/
        cp -r $DTBO $ANYKERNELDIR/
        cp -r $DTB $ANYKERNELDIR/
        cd $ANYKERNELDIR
        sed -i "s/is_slot_device=0/is_slot_device=auto/g" anykernel.sh
        zip -r9 "$ZIPNAME" * -x '*.git*' README.md *placeholder
        cd -
        echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
        echo ""
        echo -e "$ZIPNAME is ready!"
        mv $ANYKERNELDIR/$ZIPNAME $PWDIR/ZIPOUT/
        rm -rf $ANYKERNELDIR
        ls $PWDIR/ZIPOUT/
        echo ""
    else
        echo -e "\n Compilation Failed!"
    fi
}

generate_message() {
    MSG=$(sed 's/$/\\n/g' ${PWDIR}/Infomation.md | tr -d '\n')
}

generate_release_data() {
    cat <<EOF
{
"tag_name":"${BUILD_TIME}",
"target_commitish":"main",
"name":"${ZIPNAME}",
"body":"$MSG",
"draft":false,
"prerelease":${PRERELEASE},
"generate_release_notes":false
}
EOF
}

create_release() {
    echo "Creating Release"
    generate_message
    url=https://api.github.com/repos/DoraCore-Projects/build-scripts/releases
    upload_url=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: token ${GH_TOKEN}" \
        $url \
        -d "$(generate_release_data)" | jq -r .upload_url | cut -d { -f'1')
}

upload_release_file() {
    command="curl -s -o /dev/null -w '%{http_code}' \
        -H 'Authorization: token ${GH_TOKEN}' \
        -H 'Content-Type: $(file -b --mime-type ${1})' \
        --data-binary @${1} \
        ${upload_url}?name=$(basename ${1})"

    http_code=$(eval $command)
    if [ $http_code == "201" ]; then
        echo "asset $(basename ${1}) uploaded"
    else
        echo "upload failed with code '$http_code'"
        exit 1
    fi
}

for BUILD_VARIANT in ${BUILD_VARIANTS[@]}; do
    git reset --hard ${commit_sha}
    echo "Build Variant: ${BUILD_VARIANT}"
    export ZIPNAME="DoraCore-${BUILD_VARIANT}-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip"
    if [ x$BUILD_VARIANT == xMIUI ]; then
        git cherry-pick 18e95730e4e2cc796674f888dfbced069b69895c
    fi
    start_build
done

if [ -f $PWDIR/ZIPOUT/DoraCore-MIUI-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip ] && [ -f $PWDIR/ZIPOUT/DoraCore-OSS-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip ]; then
    # Create Release
    create_release
else
    echo "Build Failed !!!"
    exit 1
fi

# Upload Release Assets
for BUILD_VARIANT in ${BUILD_VARIANTS[@]}; do
    upload_release_file $PWDIR/ZIPOUT/DoraCore-${BUILD_VARIANT}-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip
done
