# 보안 정책

## 취약점 신고

이 저장소의 예제나 Orbit CLI 연동과 관련된 보안 취약점을 발견하셨다면 **공개 Issue로 올리지 말고** 아래 방법 중 하나로 비공개 신고해 주십시오.

- GitHub **Private vulnerability reporting**: 저장소의 **Security** 탭 → **Report a vulnerability**
- 이메일: support@oliveworks.io (제목에 `[SECURITY]`를 붙여 주십시오)

신고에는 다음 내용을 포함해 주시면 확인이 빨라집니다.

- 영향을 받는 파일과 예제 (예: `github-actions/orbit-gate.yml`)
- 취약점 설명과 재현 방법
- 예상되는 영향
- 사용한 Orbit CLI 버전과 CI 환경

신고를 받으면 확인 후 회신드리며, 수정이 배포되기 전에는 내용을 공개하지 않도록 협조를 부탁드립니다.

## 적용 범위

| 대상 | 신고 경로 |
|---|---|
| 이 저장소의 예제 코드와 설정 (파이프라인 샘플, 스크립트) | 이 문서의 방법 |
| Orbit CLI 이미지(`ghcr.io/oliveworks-io/orbit-cli`), Orbit Security 제품 | support@oliveworks.io |

## 인증 정보 유출 방지와 대응

이 저장소는 공개 저장소이므로 인증 정보(CI 인증 키의 `client_id`/`client_secret`, 토큰, 키 파일 등)를 커밋하거나 Issue, PR, 로그에 붙여 넣지 마십시오.

**방어 장치**

- `.gitignore`: `.env`, 키 파일, 자격 증명 파일 등을 제외합니다.
- `pre-commit` + gitleaks: 커밋 전에 검사합니다. (`pip install pre-commit && pre-commit install`)
- `secret-scan` 워크플로: 모든 push와 PR에서 전체 이력을 검사합니다.
- GitHub **Secret scanning**과 **Push protection**: 저장소 설정에서 켭니다.

**유출이 의심될 때**

1. 해당 값을 **즉시 폐기하고 재발급**합니다. (Orbit Console의 Settings > 플랫폼 관리에서 CI 인증 키 재발급)
2. 커밋 이력을 지워도 이미 노출된 값은 안전하지 않으므로, 폐기와 재발급이 우선입니다.
3. 필요하면 이력에서 제거하고(예: `git filter-repo`) support@oliveworks.io로 알려 주십시오.

## 예제 사용 시 유의 사항

> [!WARNING]
> 이 저장소의 예제는 Orbit CLI 사용 방법을 보여 주는 샘플이며, 보안 모범 사례나 표준 파이프라인 구성을 제시하지 않습니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 운영 환경에는 조직의 보안 정책에 맞게 검토하고 수정한 뒤 적용하십시오.

- 운영 파이프라인에 적용하기 전에 테스트 파이프라인에서 먼저 확인하십시오.
- API 토큰 등 인증 정보는 CI의 시크릿 저장소에 보관하고, 코드나 로그에 노출하지 마십시오.
