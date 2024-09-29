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
echo -e "${YELLOW}보유하신 모든 Proxy를 chatgpt에게 다음과 같은 형식으로 변환해달라고 하세요.${NC}"
echo -e "${YELLOW}이러한 형태로 각 프록시를 한줄에 하나씩 입력하세요: http://username:password@proxy_host:port${NC}"
echo -e "${YELLOW}프록시 입력 후 엔터를 두번 누르면 됩니다.${NC}"
> proxy.txt  # proxy.txt 파일 초기화

while true; do
    read -r proxy
    if [ -z "$proxy" ]; then
        break
    fi
    echo "$proxy" >> proxy.txt
done

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

    # 노드키 초기화 및 재생성
    rm -rf /usr/local/etc/wireguard/utun.key
    rm -f /usr/local/etc/wireguard/utun.key
    mkdir -p /usr/local/etc/wireguard
    apt install wireguard-tools
    wg genkey > /usr/local/etc/wireguard/utun.key
    
    # 네트워크 설치 스크립트 시작
    echo -e "${GREEN}Network3 노드를 실행합니다.${NC}"

    # ListenPort 값을 변경하는 함수
    change_port() {
      WG_CONFIG="/root/ubuntu-node/wg0.conf"
      DEFAULT_PORT=1433
      CURRENT_PORT=$DEFAULT_PORT

      # 포트가 사용 중인지 확인
      while sudo netstat -tuln | grep -q ":$CURRENT_PORT "; do
        echo -e "${YELLOW}포트 $CURRENT_PORT 가 사용 중입니다. 다음 포트로 시도합니다.${NC}"
        CURRENT_PORT=$((CURRENT_PORT + 1))
      done

      echo -e "${GREEN}사용 가능한 포트는 $CURRENT_PORT 입니다.${NC}"

      # wg0.conf 파일의 ListenPort 값을 변경
      if [ -f "$WG_CONFIG" ]; then
        sudo sed -i "s/^ListenPort *=.*/ListenPort = $CURRENT_PORT/" "$WG_CONFIG"
        echo -e "${GREEN}ListenPort를 $CURRENT_PORT 로 변경했습니다.${NC}"
      else
        echo -e "${RED}$WG_CONFIG 파일을 찾을 수 없습니다.${NC}"
        exit 1
      fi

      # 포트 열기
      sudo ufw allow $CURRENT_PORT
      echo -e "${GREEN}포트 $CURRENT_PORT 을(를) 방화벽에서 열었습니다.${NC}"
    }

    # 포트 변경 함수 호출
    change_port  # 이 부분 추가

    # 노드를 백그라운드에서 실행하는 함수
    sudo -E bash /root/ubuntu-node/manager.sh up
    
    # 개인키 확인
    req "노드의 개인키를 확인하시고 적어두세요." sudo -E bash /root/ubuntu-node/manager.sh key

    # IP 주소 확인
    IP_ADDRESS=$(curl -s ifconfig.me)
    if [ -z "$IP_ADDRESS" ]; then
        echo -e "${RED}IP 주소 확인에 실패했습니다. 다음 프록시로 넘어갑니다.${NC}"
        continue
    fi
    req "사용자의 IP주소를 확인합니다." echo "사용자의 IP는 ${IP_ADDRESS}입니다."
    
    # 웹계정과 연동
    URL="https://account.network3.ai/main?o=${IP_ADDRESS}:8080"
    echo "You can access the dashboard by opening https://account.network3.ai/main?o=$(hostname -I | awk '{print $1}'):$PORT in Chrome." >&2
    echo -e "${GREEN}웹계정과 연동을 진행합니다.${NC}"
    echo -e "${YELLOW}다음 URL로 접속하세요: ${URL}${NC}"
    echo -e "${YELLOW}1. 좌측 상단의 Login버튼을 누르고 이메일 계정으로 로그인을 진행하세요.${NC}"
    echo -e "${YELLOW}2. 다시 URL로 접속하신 후 Current node에서 +버튼을 누르고 노드의 개인키를 적어주세요.${NC}"
    
    # 사용자 확인을 위해 입력 대기
    echo -e "${BOLD}계속 진행하려면 엔터를 눌러 주세요.${NC}"
    read -r  # 사용자가 엔터를 누르기를 기다림

done

echo -e "${GREEN}모든 작업이 완료되었습니다. 컨트롤+A+D로 스크린을 종료해주세요.${NC}"
echo -e "${GREEN}스크립트 작성자: https://t.me/kjkresearch${NC}"
