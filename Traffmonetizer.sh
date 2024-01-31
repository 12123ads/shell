#!/bin/bash
token=$(curl -s https://token.xzhnb.workers.dev/)

# 检查容器是否存在，如果存在则删除
if [ "$(docker ps -a -f name=tm -q)" ]; then
    docker rm -f tm
fi

# 检查镜像是否存在，如果存在则删除
images=("cli:latest" "cli:arm64v8" "cli:arm32v7")
for image in "${images[@]}"; do
    if [[ "$(docker images -q $image 2> /dev/null)" != "" ]]; then
        docker rmi $image
    fi
done

arch=$(uname -m)
echo $arch
if [ "$arch" = "x86_64" ]; then
    echo "x86 architecture"
    docker run -i --name tm traffmonetizer/cli_v2:latest start accept --token $token
elif [ "$arch" = "aarch64" ]; then
    echo "aarch64 architecture"
    docker run -i --name tm traffmonetizer/cli_v2:arm64v8 start accept --token $token
elif [ "$arch" = "armv7l" ]; then
    echo "arm32 architecture"
    docker run -i --name tm traffmonetizer/cli_v2:arm32v7 start accept --token $token
else
    echo "Unknown architecture"
fi
