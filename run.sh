#!/bin/bash
#set -e

git config --local user.name "dopaemon"
git config --local user.email "polarisdp@gmail.com"

# Export Vars
export PWDIR=$(pwd)
export KERNELDIR=$PWDIR/13
export ANYKERNELDIR=$PWDIR/Anykernel3
export KERNEL_DEFCONFIG=vendor/sweet_user_defconfig
export BUILD_TIME=$(date +"%Y%m%d-%H%M%S")
export ARCH=arm64
export SUBARCH=arm64
export ZIPNAME=XYZABC

export BUILD_TYPE=canary
export PRERELEASE=true
echo "Build Type: Canary"
if [ x${1} == xstable ]; then
export BUILD_TYPE=stable
export PPRERELEASE=false
echo "Build Type: Stable"
fi

# Clone kernel
echo -e "$green << cloning kernel >> \n $white"
git clone https://${GH_TOKEN}@github.com/DoraCore-Projects/android_kernel_xiaomi_sweet.git $KERNELDIR
cd $KERNELDIR

# Cleanup
rm -rf $PWDIR/ZIPOUT
rm -rf $KERNELDIR/out

# Update Submodules
git submodule init
git submodule update
git submodule update --recursive --remote
git add -vAf
git commit -sm "KernelSU: Latest commit"

export commit_sha=$(git rev-parse HEAD)
echo -e "Latest commit is: "${commit_sha}

sleep 5

mkdir -p $PWDIR/ZIPOUT

# Tool Chain
echo -e "$green << cloning gcc from arter >> \n $white"
git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 "$PWDIR"/gcc64
git clone --depth=1 https://github.com/mvaisakh/gcc-arm "$PWDIR"/gcc32
export PATH="$PWDIR/gcc64/bin:$PWDIR/gcc32/bin:$PATH"
export KBUILD_COMPILER_STRING=$("$PWDIR"/gcc64/bin/aarch64-elf-gcc --version | head -n 1)

# Clang
echo -e "$green << cloning clang >> \n $white"
git clone -b 15 --depth=1 https://gitlab.com/PixelOS-Devices/playgroundtc.git "$PWDIR"/clang
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
    export IMGDTB=$KERNELDIR/out/arch/arm64/boot/Image.gz-dtb

    if [ -f $IMGDTB ]; then
        echo "------ Finishing Build ------"
        git clone https://${GH_TOKEN}@github.com/DoraCore-Projects/Anykernel3.git $ANYKERNELDIR
        cp $IMGDTB $ANYKERNELDIR
        cd $ANYKERNELDIR
        zip -r9 "$ZIPNAME" * -x '*.git*' README.md *placeholder
        cd -
        echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
        echo ""
        echo -e "$ZIPNAME is ready!"
        mv $ANYKERNELDIR/$ZIPNAME $PWDIR/ZIPOUT/
        ls $PWDIR/ZIPOUT/
        echo ""
    else
        echo -e "\n Compilation Failed!"
    fi
}

build_kernel() {
    for ((i = 1; i <= 2; i++)); do
        case $i in
            1)
                git reset --hard ${commit_sha}
                echo "Default - OSS"
                export ZIPNAME="DoraCore-OSS-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip"
                start_build
                ;;
#            2)
#                git reset --hard ${commit_sha}
#                echo "MIUI"
#                export ZIPNAME="DoraCore-MIUI-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip"
#                git cherry-pick bbb51e5f51f597e577b00121652f68ea8e656859
#                start_build
#                ;;
            *)
                echo "Error"
                ;;
        esac
    done
}

generate_message() {
MSG=$(sed 's/$/\\n/g' ${CURDIR}/changelog.md)
}

generate_release_data() {
    cat <<EOF
{
"tag_name":"${BUILD_TIME}",
"target_commitish":"main",
"name":"${ZIPNAME}",
"body":"${MSG}",
"draft":false,
"prerelease":${PRERELEASE},
"generate_release_notes":false
}
EOF
}

create_release() {
    echo "Creating Release"
    url=https://api.github.com/repos/DoraCore-Projects/build-scripts/releases
    echo "$url"
    upload_url=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: token ${GH_TOKEN}" \
        $url \
        -d "$(generate_release_data)" | jq -r .upload_url | cut -d { -f'1')
    echo "$upload_url"
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

tg_upload() {
    TOKEN="$TG_TOKEN"
    CHAT_ID="-1001980325626"
    MESSAGE="DoraCore Canary ${date}"
    DIRECTORY="$PWDIR/ZIPOUT"
    # Đường dẫn đến thư mục chứa các file zip
    FOLDER_PATH="$PWDIR/ZIPOUT"

    # Tạo một mảng chứa các file zip
    declare -a FILE_ARRAY

    # Lặp qua tất cả các file zip trong thư mục và thêm vào mảng
    for FILE_PATH in "$FOLDER_PATH"/*.zip; do
        FILE_ARRAY+=("-F" "document=@\"$FILE_PATH\"")
    done

    # Gửi tin nhắn với cả 4 file đính kèm
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        "${FILE_ARRAY[@]}"
}

build_kernel
create_release
upload_release_file $PWDIR/ZIPOUT/$ZIPNAME
