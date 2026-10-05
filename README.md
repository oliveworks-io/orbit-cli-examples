# orbit-cli-examples

Orbit CLI(빌드 게이트 CLI)를 CI/CD 파이프라인에 연동하는 예제 모음입니다.

Orbit CLI는 빌드 단계에서 컨테이너 이미지의 SBOM을 만들어 Orbit Security 서버에 올리고, 서버가 내린 판정을 **종료 코드**로 CI에 전달합니다. 이 저장소는 도구별로 바로 가져다 쓸 수 있는 파이프라인 샘플과 설명을 제공합니다. CLI 자체의 명령·옵션·출력은 Orbit Security 사용자 매뉴얼의 "빌드 게이트 CLI" 절을 참고합니다.

> [!WARNING]
> **이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플입니다.**
>
> - 보안 모범 사례나 표준 파이프라인 구성을 제시하는 것이 목적이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 액션과 이미지의 버전 고정, 네트워크 제한 같은 항목은 단순화했거나 생략했을 수 있습니다.
> - 예제를 그대로 운영 파이프라인에 적용하지 마십시오. 조직의 보안 정책과 CI 환경에 맞게 검토하고 수정한 뒤, 테스트 파이프라인에서 먼저 확인하십시오.
> - 예제는 어떠한 보증 없이 "있는 그대로" 제공되며, 사용으로 인한 책임은 사용자에게 있습니다. 자세한 내용은 [LICENSE](LICENSE)를 참고하십시오.

## 예제 목록

| CI/CD 도구 | 폴더 | 파이프라인 샘플 |
|---|---|---|
| Jenkins | [jenkins](jenkins) | `Jenkinsfile` |
| GitLab CI | [gitlab-ci](gitlab-ci) | `.gitlab-ci.yml` |
| GitHub Actions | [github-actions](github-actions) | `orbit-gate.yml` |
| Tekton Pipelines(JayeX 포함) | [tekton](tekton) | `orbit-build-gate-task.yaml` |
| 기타 CI, CI 없는 환경 | [other-ci](other-ci) | `orbit-gate.sh` |

각 폴더의 `README.md`에 사전 준비, 샘플 사용법, 동작 확인, 문제 해결이 있습니다.

## 시작하기 전에

### 1. CI 인증 키 발급

파이프라인이 서버에 접속할 때 쓰는 `client_id`와 `client_secret`입니다. Orbit Console에서 **Settings > 플랫폼 관리**로 이동해 CI/CD 도구를 등록하고 CI 인증 키를 발급합니다. 두 값은 발급 직후에만 확인할 수 있으니 바로 CI의 비밀 저장소에 등록합니다. 자세한 방법은 사용자 매뉴얼의 "CI 인증 키 발급 및 관리"에 있습니다.

CI 도구의 비밀 저장소에 다음 두 값을 등록합니다.

| 이름 | 값 |
|---|---|
| `ORBIT_CLIENT_ID` | CI 인증 키의 client_id |
| `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret(비밀 값으로 등록) |

조직 ID는 등록하지 않습니다. 인증 토큰에 이미 들어 있습니다.

### 2. CLI 이미지 digest 확인

CLI 컨테이너 이미지는 **태그가 아니라 digest로 고정**해서 씁니다. 같은 태그에 다른 내용이 올라가면 어제 통과한 빌드가 오늘 다른 바이너리로 실행될 수 있기 때문입니다.

```sh
crane digest ghcr.io/oliveworks-io/orbit-cli:2.0.0
```

확인한 값을 샘플의 `<64자 hex>` 자리에 넣습니다.

```text
ghcr.io/oliveworks-io/orbit-cli:2.0.0@sha256:<64자 hex>
```

> TBD: `2.0.0` 태그의 공개 여부와 공식 digest 목록 안내 위치는 확정되지 않았습니다.

### 3. 서버 주소와 발급자

서버 주소(`ORBIT_ADDRESS`)와 인증 서버 주소(`ORBIT_ISSUER`)는 CLI 컨테이너 이미지에 이미 들어 있어 보통 지정하지 않습니다. 설치형(폐쇄망) 환경처럼 주소가 다른 경우에는 설치 담당자에게 받은 값을 환경변수로 지정하고, 컨테이너 실행 때 `-e ORBIT_ADDRESS -e ORBIT_ISSUER`로 넘깁니다. 값에는 `https://`까지 적습니다.

> 빈 값을 `-e`로 넘기지 않습니다. 이름만 있는 `-e VAR`는 빈 문자열도 그대로 넘겨서 이미지에 들어 있는 기본값을 덮어씁니다.

## 모든 예제에 공통인 원칙

1. **빌드는 push 없이 합니다.** 판정 전에 레지스트리에 올라가면 게이트의 의미가 없습니다.
2. **판정 전에 최종 이미지 참조로 태그합니다.** 하지 않으면 이미지 좌표가 `docker.io/library/…:candidate`로 남습니다.
3. **판정한 이미지를 그대로 push합니다.** 다시 빌드해서 올리면 digest가 어긋납니다.
4. **종료 코드가 `0`이 아니면 중단합니다.** 차단(`1`)뿐 아니라 오류(`2`)도 통과가 아닙니다.
5. **CI 환경변수를 컨테이너에 `-e`로 넘깁니다.** CLI 컨테이너는 CI 러너의 환경변수를 물려받지 않아서, 넘기지 않으면 빌드 좌표를 자동으로 얻지 못합니다.
6. **`--pipeline-ref`는 실행마다 달라지지 않는 값으로 고정합니다.** 자동 인식 대상이 아닌 도구(Tekton, 기타 CI)에서만 직접 지정합니다. 실행마다 바뀌는 값(커밋, 빌드 번호)은 `--ci-run-id`에 넣습니다.

## 종료 코드

| 코드 | 의미 | 파이프라인 동작 |
|:-:|---|---|
| `0` | 통과 | 다음 단계로 진행합니다. |
| `1` | 게이트 위반으로 차단 | 단계를 실패시키고 이후 단계를 건너뜁니다. |
| `2` | 오류(인증, 네트워크, 시간 초과 등) | 단계를 실패시킵니다. |

`0`에는 위반이 없는 경우와, 위반은 있지만 조직 설정에서 차단을 사용하지 않는 경우가 모두 들어 있습니다. 출력의 `GATE` 줄로 구분합니다.

## 문제가 생기면

먼저 `orbit doctor`를 실행합니다. 서버에 접속하지 않고, 빌드 좌표와 자격이 어떻게 해석되는지만 보여 줍니다. 도구별 실행 방법은 각 폴더의 `README.md`에 있습니다.

## 예제 검증 상태

| 도구 | 검증 상태 |
|---|---|
| Jenkins | TBD |
| GitLab CI | TBD |
| GitHub Actions | TBD |
| Tekton Pipelines | TBD |
| 기타 CI | TBD |

> 샘플은 Orbit CLI 2.0.0 기준으로 작성했습니다. 사용하는 CI 환경에 맞춰 이미지 이름, 변수 이름, 러너 구성을 조정하고, 운영 파이프라인에 적용하기 전에 테스트 파이프라인에서 먼저 확인하십시오.

## 문의

제품 사용과 연동 문의는 support@oliveworks.io로 보내 주십시오.

## 라이선스

Copyright 2026 OliveWorks Inc.

이 저장소의 예제는 [Apache License 2.0](LICENSE)에 따라 사용할 수 있습니다.

Orbit CLI 컨테이너 이미지(`ghcr.io/oliveworks-io/orbit-cli`)와 Orbit Security 제품의 사용 조건은 이 저장소의 라이선스와 별개입니다.
# orbit-cli-examples
