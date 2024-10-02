#!/bin/bash

# 색깔 변수 정의
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Network3 노드 설치를 시작합니다.${NC}"

# 사용자에게 명령어 결과를 강제로 보여주는 함수
req() {
  echo -e "${YELLOW}$1${NC}"
  shift
  "$@"
  echo -e "${YELLOW}결과를 확인한 후 엔터를 눌러 계속 진행하세요.${NC}"
  read -r
}

# Docker 설치 확인 및 설치
if ! [ -x "$(command -v docker)" ]; then
  echo -e "${YELLOW}Docker가 설치되어 있지 않습니다. Docker를 설치합니다...${NC}"
  bash install_docker.sh
fi

# /root/ubuntu-node 폴더가 존재하면 삭제합니다.
if [ -d "/root/ubuntu-node" ]; then
  echo -e "${RED}/root/ubuntu-node 폴더가 존재하므로 삭제합니다.${NC}"
  sudo rm -rf /root/ubuntu-node
fi

# 디렉토리 생성
sudo mkdir -p /root/ubuntu-node

# 파일 다운로드 및 압축 해제
cd /root/ubuntu-node

sudo git clone https://github.com/KangJKJK/network3-base /root/ubuntu-node

# 프록시 입력받기
echo -e "${YELLOW}보유하신 모든 Proxy를 다음과 같은 형식으로 입력하세요:${NC}"
echo -e "${YELLOW}http://username:password@proxy_host:port${NC}"
echo -e "${YELLOW}프록시 입력 후 엔터를 두 번 누르면 됩니다.${NC}"
> proxy.txt  # proxy.txt 파일 초기화

while true; do
    read -r proxy
    if [ -z "$proxy" ]; then
        break
    fi
    echo "$proxy" >> proxy.txt
done

# 시작 포트 설정
HOST_START_PORT=1433

# change_ports.sh 스크립트 생성
cat <<'EOF' > change_ports.sh
#!/bin/bash

echo "포트 변경 스크립트가 실행되었습니다."

WG_CONFIG="/root/ubuntu-node/wg0.conf"

# 환경 변수로 전달된 시작 포트, 기본값은 1433
START_PORT=${START_PORT:-1433}
CURRENT_PORT=$START_PORT

# 포트가 사용 중인지 확인하고 사용 가능한 포트 찾기
while ss -tuln | grep -q ":$CURRENT_PORT "; do
  echo -e "\033[0;33m포트 $CURRENT_PORT 이(가) 사용 중입니다. 다음 포트로 시도합니다.\033[0m"
  CURRENT_PORT=$((CURRENT_PORT + 1))
done

echo -e "\033[0;32m사용 가능한 포트는 $CURRENT_PORT 입니다.\033[0m"

# wg0.conf 파일의 ListenPort 값을 변경
if [ -f "$WG_CONFIG" ]; then
  sed -i "s/^ListenPort = .*/ListenPort = $CURRENT_PORT/" "$WG_CONFIG"
  echo -e "\033[0;32mListenPort를 $CURRENT_PORT 로 변경했습니다.\033[0m"
else
  echo -e "\033[0;31m$WG_CONFIG 파일을 찾을 수 없습니다.\033[0m"
  exit 1
fi

# 포트 열기
ufw allow $CURRENT_PORT
echo -e "\033[0;32m포트 $CURRENT_PORT 을(를) 방화벽에서 열었습니다.\033[0m"

# manager.sh 스크립트 실행
bash /root/ubuntu-node/manager.sh up
EOF

# utun.key 파일 생성 (한 번만 생성)
if [ ! -f utun.key ]; then
  wg genkey > utun.key
  chmod 600 utun.key
fi

# 모든 프록시 처리
for proxy in $(< proxy.txt); do
    # 프록시가 비어있으면 넘어감
    if [ -z "$proxy" ]; then
        echo -e "${RED}프록시가 입력되지 않았습니다. 다음 프록시로 넘어갑니다.${NC}"
        continue  
    fi

    echo -e "${GREEN}프록시 ${proxy}로 노드를 백그라운드에서 실행합니다.${NC}"
    export http_proxy="$proxy"  # 프록시 설정
    export https_proxy="$proxy"  # HTTPS 프록시 설정

    # 네트워크 설치 스크립트 시작
    echo -e "${GREEN}Network3 노드를 실행합니다.${NC}"

    # Docker 컨테이너 이름 생성 (프록시 해시 및 타임스탬프 추가)
    container_name="network3_node_$(echo $proxy | md5sum | cut -d' ' -f1)_$(date +%s)"

    # 호스트 포트 할당
    HOST_PORT=$HOST_START_PORT

    # 사용 가능한 호스트 포트 찾기
    while ss -tuln | grep -q ":$HOST_PORT " ; do
      echo -e "${YELLOW}호스트 포트 $HOST_PORT 이(가) 사용 중입니다. 다음 포트로 시도합니다.${NC}"
      HOST_PORT=$((HOST_PORT + 1))
    done

    echo -e "${GREEN}호스트 포트는 $HOST_PORT 입니다.${NC}"

    # Dockerfile 생성
    cat <<EOF > Dockerfile
FROM ubuntu:latest

# 필수 패키지 설치
RUN apt-get update && apt-get install -y wireguard-tools curl net-tools iptables dos2unix ufw iproute2

# Node.js 설치
RUN curl -fsSL https://deb.nodesource.com/setup_14.x | bash - && \
    apt-get install -y nodejs

# 작업 디렉토리로 이동
WORKDIR /root/ubuntu-node

# change_ports.sh 스크립트 복사
COPY change_ports.sh /root/ubuntu-node/change_ports.sh
RUN chmod +x /root/ubuntu-node/change_ports.sh

# wg0.conf 파일 복사
COPY wg0.conf /root/ubuntu-node/wg0.conf

# manager.sh 파일 복사
COPY manager.sh /root/ubuntu-node/manager.sh
RUN chmod +x /root/ubuntu-node/manager.sh

# utun.key 파일 복사 및 권한 설정
COPY utun.key /usr/local/etc/wireguard/utun.key
RUN chmod 600 /usr/local/etc/wireguard/utun.key

# 스크립트 실행 시 포트 환경 변수 전달
ENV START_PORT=$HOST_PORT

# 스크립트 실행
ENTRYPOINT ["bash", "/root/ubuntu-node/change_ports.sh"]
EOF

    # Docker 이미지 빌드
    docker build --no-cache -t $container_name .

    # Docker 컨테이너 실행 시 호스트 포트와 컨테이너 포트 매핑
    docker run --privileged -d --name $container_name \
        -p $HOST_PORT:1433 \
        --env http_proxy=$http_proxy \
        --env https_proxy=$https_proxy \
        $container_name

    # 개인키 확인
    req "노드의 개인키를 확인하시고 적어두세요." docker exec -it $container_name bash -c "cat /usr/local/etc/wireguard/utun.key"

    # IP 주소 확인
    IP_ADDRESS=$(curl -s ifconfig.me)
    if [ -z "$IP_ADDRESS" ]; then
        echo -e "${RED}IP 주소 확인에 실패했습니다. 다음 프록시로 넘어갑니다.${NC}"
        continue
    fi
    req "사용자의 IP주소를 확인합니다." echo "사용자의 IP는 ${IP_ADDRESS}입니다."

    # 웹계정과 연동
    URL="http://account.network3.ai:8080/main?o=${IP_ADDRESS}:8080"
    echo "You can access the dashboard by opening ${URL} in Chrome." >&2
    echo -e "${GREEN}웹계정과 연동을 진행합니다.${NC}"
    echo -e "${YELLOW}다음 URL로 접속하세요: ${URL}${NC}"
    echo -e "${YELLOW}1. 좌측 상단의 Login버튼을 누르고 이메일 계정으로 로그인을 진행하세요.${NC}"
    echo -e "${YELLOW}2. 다시 URL로 접속하신 후 Current node에서 +버튼을 누르고 노드의 개인키를 적어주세요.${NC}"

    # 사용자 확인을 위해 입력 대기
    echo -e "${BOLD}계속 진행하려면 엔터를 눌러 주세요.${NC}"
    read -r  # 사용자가 엔터를 누르기를 기다림

    # 호스트 포트 증가
    HOST_START_PORT=$((HOST_PORT + 1))

done

echo -e "${GREEN}모든 작업이 완료되었습니다. 컨트롤+A+D로 스크린을 종료해주세요.${NC}"
echo -e "${GREEN}스크립트 작성자: https://t.me/kjkresearch${NC}"
