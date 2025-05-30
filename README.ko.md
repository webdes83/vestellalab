# Proxmox 자동화 스크립트

🇬🇧 [English](README.md) | 🇰🇷 [한국어](README.ko.md)

이 저장소는 Proxmox 환경에서 유용하게 사용할 수 있는 자동화 스크립트를 포함하고 있습니다.

## 제공 스크립트

### `proxmox/xterm_setup.sh`

Proxmox VM에 xterm.js 기반 시리얼 콘솔 접속을 자동 설정해주는 스크립트입니다.

#### 사용 방법

```bash
curl -fsSL https://raw.githubusercontent.com/webdes83/vestellalab/refs/heads/main/proxmox/xterm_setup.sh | bash -s -- <VMID>
```

`<VMID>`는 대상 가상머신의 ID로 변경하여 사용하십시오.

#### 수행 작업

- VM이 실행 중인지 확인
- `qemu-guest-agent` 설치 여부 확인
- `/etc/default/grub`에 `console=ttyS0` 추가 (없을 경우)
- `update-grub` 실행
- `serial-getty@ttyS0.service` 활성화
- VM 설정에 `serial0: socket` 항목 추가
- VM 재부팅

---

### `proxmox/auto_note_network.sh`

Proxmox LXC/VM의 Notes(설명) 영역에 네트워크 정보를 자동으로 반영합니다.

- LXC와 VM 모두 지원 (ID로 자동 판별)
- 맨 위 `[Auto] 네트워크 정보` 영역만 덮어쓰고, 아래 기존 Note는 그대로 보존
- VM의 경우 `/etc/NetworkManager/system-connections/*` 내 커스텀 라우팅·IP 등도 노출
- 변경사항은 diff와 ~~취소선~~으로 표시

**사용 예시:**
```bash
curl -fsSL https://raw.githubusercontent.com/webdes83/vestellalab/refs/heads/main/proxmox/auto_note_network.sh | bash -s -- <VMID|CTID>
```

### 기여 안내
스크립트 개선이나 기능 추가를 위한 이슈 및 PR을 환영합니다.

### 라이선스
MIT License
