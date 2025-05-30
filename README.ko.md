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

Proxmox VM/CT 네트워크·방화벽·MAC·게스트 인터페이스 매핑 정보를 수집하여  
Markdown 형식으로 출력하거나 VM/CT description 필드에 자동 반영해 주는 스크립트입니다.

---

## 요구사항

- bash (Associative Array 지원)
- `jq` (JSON 파싱)
- `yq` (YAML → JSON 변환)
- Proxmox CLI 도구: `pvesh`, `qm`, `pct`
- Proxmox VE 7.x 이상

---

## 설치 및 실행

**사용 예시:**
```bash
# 디버그 모드 + 적용: ID가 103인 VM, 실행 로그와 함께 description 갱신
curl -fsSL https://raw.githubusercontent.com/webdes83/vestellalab/main/proxmox/auto_note_network.sh \
  | bash -s -- -d -a --id 103 <VMID|CTID>
```

### 기여 안내
스크립트 개선이나 기능 추가를 위한 이슈 및 PR을 환영합니다.

### 라이선스
MIT License
