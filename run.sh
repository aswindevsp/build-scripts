#!/bin/bash
#set -e
# Clone kernel
export PWDIR=$(pwd)
echo -e "$green << cloning kernel >> \n $white"
git clone https://${GH_TOKEN}@github.com/DoraCore-Projects/android_kernel_xiaomi_sweet.git 13
cd 13
# git submodule init
# git submodule update

# git submodule update --recursive --remote

rm -rf ZIPOUT

rm -rf out

git config --local user.name "dopaemon"
git config --local user.email "polarisdp@gmail.com"

# git add -vAf

# git commit -sm "KernelSU: Latest commit"

export commit_sha=$(git rev-parse HEAD)

echo -e "Latest commit is: "${commit_sha}

sleep 5

export KERNEL_DEFCONFIG=vendor/sweet_user_defconfig
export date=$(date +"%Y-%m-%d-%H%M")
export ARCH=arm64
export SUBARCH=arm64
mkdir -p ZIPOUT

# Tool Chain
echo -e "$green << cloning gcc from arter >> \n $white"
git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 "$PWDIR"/../gcc64
git clone --depth=1 https://github.com/mvaisakh/gcc-arm "$PWDIR"/../gcc32
export PATH="$PWDIR/../gcc64/bin:$PWDIR/../gcc32/bin:$PATH"
export STRIP="$PWDIR/../gcc64/aarch64-elf/bin/strip"
export KBUILD_COMPILER_STRING=$("$PWDIR"/../gcc64/bin/aarch64-elf-gcc --version | head -n 1)

# Clang
echo -e "$green << cloning clang >> \n $white"
git clone -b 15 --depth=1 https://gitlab.com/PixelOS-Devices/playgroundtc.git "$PWDIR"/../clang
export PATH="$PWDIR/../clang/bin:$PATH"
export KBUILD_COMPILER_STRING=$("$PWDIR"/../clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')


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
        make -j$(nproc --all) O=out \
                                      ARCH=arm64 \
                                      LLVM=1 \
                                      LLVM_IAS=1 \
                                      AR=llvm-ar \
                                      NM=llvm-nm \
                                      LD=ld.lld \
                                      OBJCOPY=llvm-objcopy \
                                      OBJDUMP=llvm-objdump \
                                      STRIP=llvm-strip \
                                      CC=clang \
                                      CROSS_COMPILE=aarch64-linux-gnu- \
                                      CROSS_COMPILE_ARM32=arm-linux-gnueabi-  2>&1 | tee error.log
        export IMG="$MY_DIR"/out/arch/arm64/boot/Image.gz
        export dtbo="$MY_DIR"/out/arch/arm64/boot/dtbo.img
        export dtb="$MY_DIR"/out/arch/arm64/boot/dtb.img

        find out/arch/arm64/boot/dts/ -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb
        if [ -f "out/arch/arm64/boot/Image.gz" ] && [ -f "out/arch/arm64/boot/dtbo.img" ] && [ -f "out/arch/arm64/boot/dtb" ]; then
                echo "------ Finishing  Build ------"
                git clone -q https://github.com/Sweet-stuff/AnyKernel3
                cp out/arch/arm64/boot/Image.gz AnyKernel3
                cp out/arch/arm64/boot/dtb AnyKernel3
                cp out/arch/arm64/boot/dtbo.img AnyKernel3
                rm -f *zip
                cd AnyKernel3
                sed -i "s/is_slot_device=0/is_slot_device=auto/g" anykernel.sh
                zip -r9 "../${zipname}" * -x '*.git*' README.md *placeholder >> /dev/null
                cd ..
                rm -rf AnyKernel3
                echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
                echo ""
                echo -e ${zipname} " is ready!"
                mv ${zipname} ZIPOUT/
                echo ""
        else
                echo -e "\n Compilation Failed!"
        fi
}

canary_build() {
for ((i=1; i<=4; i++))
do
    case $i in
        1)
            git reset --hard ${commit_sha}
            echo "Miui Normal"
            export zipname="DoraCore-Miui-Canary-sweet-${date}.zip"
#            git cherry-pick bbb51e5f51f597e577b00121652f68ea8e656859
#            git cherry-pick 0ac291bba8a6f8a57c581bab651f78a95f460e19
            start_build
            ;;
#        2)
#            git reset --hard ${commit_sha}
#            echo "Miui Ksu"
#            export zipname="DoraCore-KernelSU-Miui-Canary-sweet-${date}.zip"
#            git cherry-pick bbb51e5f51f597e577b00121652f68ea8e656859
#            git cherry-pick b609eaa139b4a7a9e97191351da39ba9bfaf73ea
#            start_build
#            ;;
#        3)
#            git reset --hard ${commit_sha}
#            echo "OSS Normal"
#            export zipname="DoraCore-OSS-Canary-sweet-${date}.zip"
#            git cherry-pick dc8508f83153ed010903ff359617a45010985ac7
#            git cherry-pick 0ac291bba8a6f8a57c581bab651f78a95f460e19
#            start_build
#            ;;
#        4)
#            git reset --hard ${commit_sha}
#            echo "OSS Ksu"
#            export zipname="DoraCore-KernelSU-OSS-Canary-sweet-${date}.zip"
#            git cherry-pick dc8508f83153ed010903ff359617a45010985ac7
#            git cherry-pick b609eaa139b4a7a9e97191351da39ba9bfaf73ea
#            start_build
#            ;;
        *)
            echo "Error"
            ;;
    esac
done
}

tg_upload() {
TOKEN="$TG_TOKEN"
CHAT_ID="-1001980325626"
MESSAGE="DoraCore Canary ${date}"
DIRECTORY="$PWDIR/13/ZIPOUT"
# Đường dẫn đến thư mục chứa các file zip
FOLDER_PATH="$PWDIR/13/ZIPOUT"

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
tg_upload
