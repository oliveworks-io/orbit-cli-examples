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

| CI/CD 도구 | 폴더 | 적용 템플릿 | CLI 시험 |
|---|---|---|---|
| Jenkins | [jenkins](jenkins) | `Jenkinsfile` | `Jenkinsfile.cli-test` |
| GitLab CI | [gitlab-ci](gitlab-ci) | `.gitlab-ci.yml` | `.gitlab-ci.cli-test.yml` |
| GitHub Actions | [github-actions](github-actions) | `orbit-gate.yml` | — |
| Tekton Pipelines(JayeX 포함) | [tekton](tekton) | `orbit-build-gate-task.yaml` | — |
| 기타 CI, CI 없는 환경 | [other-ci](other-ci) | `orbit-gate.sh` | — |

각 폴더의 `README.md`에 사전 준비, 1단계(dry-run), 2단계(본적용), 동작 확인, 문제 해결이 있습니다.

## 진행 순서

1. **dry-run — CLI 시험(cli-test).** 이미지를 만들거나 올리지 않고 `version`, `doctor`, `scan file`로 자격·네트워크·서버 판정이 통하는지 먼저 확인합니다. Orbit 자격 두 개만 있으면 됩니다. Jenkins와 GitLab CI에 있고, 나머지 도구는 각 README의 "1단계"대로 `version`, `doctor`를 실행합니다.
2. **본적용 — 적용 템플릿.** dry-run이 통과하면 적용 템플릿을 자기 CI에 복사하고, 맨 위 "여기만 바꿉니다" 블록(`IMAGE` 등)을 채워 실행합니다.

## 시작하기 전에

### 1. CI 인증 키 발급

파이프라인이 서버에 접속할 때 쓰는 `client_id`와 `client_secret`입니다. Orbit Console에서 **Settings > 플랫폼 관리**로 이동해 CI/CD 도구를 등록하고 CI 인증 키를 발급합니다. 두 값은 발급 직후에만 확인할 수 있으니 바로 CI의 비밀 저장소에 등록합니다. 자세한 방법은 사용자 매뉴얼의 "CI 인증 키 발급 및 관리"에 있습니다.

CI 도구의 비밀 저장소에 다음 두 값을 등록합니다.

| 이름 | 값 |
|---|---|
| `ORBIT_CLIENT_ID` | CI 인증 키의 client_id |
| `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret(비밀 값으로 등록) |

조직 ID는 등록하지 않습니다. 인증 토큰에 이미 들어 있습니다.

### 2. CLI 이미지 digest

CLI 컨테이너 이미지는 **태그가 아니라 digest로 고정**해서 씁니다. 같은 태그에 다른 내용이 올라가면 어제 통과한 빌드가 오늘 다른 바이너리로 실행될 수 있기 때문입니다. 샘플은 아래 값으로 이미 고정되어 있어 바꿀 필요가 없습니다.

```text
ghcr.io/oliveworks-io/orbit-cli:2.0.1@sha256:ce55fd53b389998ee2fa125ca6e5baf944384c1f9c56f5ff2c8e9bbe1e6aceca
```

다른 버전을 쓰려면 digest를 확인해 샘플의 `ORBIT_CLI_IMAGE`(Tekton은 CLI step의 `image`)를 바꿉니다. `latest`, `2`처럼 움직이는 태그는 쓰지 않습니다.

```sh
crane digest ghcr.io/oliveworks-io/orbit-cli:<버전>
```

### 3. 서버 주소와 발급자

서버 주소(`ORBIT_ADDRESS`)와 인증 서버 주소(`ORBIT_ISSUER`)는 CLI 컨테이너 이미지에 이미 들어 있어 보통 지정하지 않습니다. 설치형(폐쇄망) 환경처럼 주소가 다른 경우에는 설치 담당자에게 받은 값을 환경변수로 지정하고, 컨테이너 실행 때 `-e ORBIT_ADDRESS -e ORBIT_ISSUER`로 넘깁니다. 값에는 `https://`까지 적습니다.

> 빈 값을 `-e`로 넘기지 않습니다. 이름만 있는 `-e VAR`는 빈 문자열도 그대로 넘겨서 이미지에 들어 있는 기본값을 덮어씁니다.

### 4. 이미지를 올릴 레지스트리

적용 템플릿은 판정한 이미지를 `IMAGE`에 지정한 레지스트리에 올립니다. 특정 레지스트리에 묶여 있지 않습니다. CLI 시험(cli-test)만 쓴다면 이 단계는 건너뜁니다.

**입력은 템플릿 맨 위 "여기만 바꿉니다" 블록 한 곳입니다.**

| 이름 | 값 |
|---|---|
| `IMAGE` | 판정하고 올릴 이미지. 예: `registry.example.com/team/myapp`. 첫 부분(`registry.example.com`)이 레지스트리 주소이며, push와 로그인 모두 이 주소로 갑니다. 레지스트리 주소를 따로 적는 변수는 없습니다. |
| `IMAGE_TAG` | 비우면 커밋 해시. 레지스트리가 태그를 따로 요구할 때만 씁니다. |
| `REGISTRY_LOGIN` | `credentials`(자격으로 로그인) 또는 `none`(로그인하지 않음). 반드시 둘 중 하나를 고릅니다. Jenkins는 `REGISTRY_CREDENTIALS_ID`에 Credentials ID 또는 `none`, Tekton은 params의 `registry-login`입니다. |

- `IMAGE`를 설정하지 않으면(`<…>` 자리표시가 남으면) Tag 단계에서 무엇을 넣어야 하는지 알려 주고 멈춥니다. 잘못된 곳으로 push되지 않습니다.
- 로그인 방식을 고르지 않으면 Push 단계에서 멈춥니다. `credentials`를 골랐는데 자격이 없어도 멈춥니다. 빈칸을 그냥 넘겨서 로그인 없이 올라가는 경로는 없습니다.
- GitLab CI와 GitHub Actions는 같은 이름의 CI 변수로 넣어도 됩니다. 이때는 파일을 고치지 않고 그대로 붙여 넣습니다.

**`credentials`를 고르면** 레지스트리 자격을 CI의 비밀 저장소에 등록합니다. 로그인 호스트는 `IMAGE`의 첫 부분에서 정합니다(점이나 포트가 없으면 `docker.io`).

| 이름 | 값 |
|---|---|
| `REGISTRY_USERNAME` | 레지스트리 사용자 이름 |
| `REGISTRY_TOKEN` | 액세스 토큰(비밀 값으로 등록) |

**가입 없이 시연할 때**는 공개 임시 레지스트리 [ttl.sh](https://ttl.sh)를 씁니다. 자격이 필요 없고, 태그가 보관 시간입니다.

| 이름 | 값 |
|---|---|
| `IMAGE` | `ttl.sh/orbit/orbit-gate-hello-<임의 문자열>` |
| `IMAGE_TAG` | `1h` (최대 `24h`) |
| `REGISTRY_LOGIN` | `none` |

> [!WARNING]
> ttl.sh에 올린 이미지는 **누구나 받을 수 있습니다.** 시연 이미지 외에는 올리지 않습니다. `IMAGE`가 `ttl.sh/`로 시작하면 Push 단계가 경고를 출력합니다. 경로를 `ttl.sh/orbit/…`처럼 두 단계로 두는 것은 이미지 좌표의 namespace가 비지 않게 하기 위해서입니다.

## 샘플 구성

샘플은 두 가지입니다.

- **적용 템플릿:** 자기 CI에 복사해 실제로 쓰는 파이프라인입니다. 이미지를 판정하고(`scan image`), 통과한 이미지를 올린 뒤 확정 digest를 보고합니다(`scan promote`).
- **CLI 시험(cli-test):** 적용 템플릿이 쓰지 않는 CLI 명령(`version`, `doctor`, `scan file`)을 하나씩 실행해 확인합니다. Jenkins와 GitLab CI에만 있습니다. 이미지를 만들거나 올리지 않으므로 레지스트리 자격이 필요 없습니다.

| 명령 | 적용 템플릿 | CLI 시험 |
|---|:-:|:-:|
| `orbit version` | | ○ |
| `orbit doctor` | | ○ |
| `orbit scan file` | | ○ |
| `orbit scan image` | ○ | |
| `orbit scan promote` | ○ | |

### 적용 템플릿

이 저장소에서 그대로 실행하면 루트의 시연용 이미지를 빌드하고, 자기 CI에 복사하면 자기 저장소의 Dockerfile을 빌드합니다. 루트의 [`Dockerfile`](Dockerfile)은 앱 소스가 없는 시연용 이미지 `orbit-gate-hello`를 만들고, [`vendor/`](vendor)의 JAR 하나를 넣습니다. 이 JAR에는 알려진 취약점(CVE-2022-42889)이 있지만 이미지에 JRE가 없어 실행 경로가 없습니다.

| 순서 | 단계 | 명령 | 하는 일 | 멈추는 경우 |
|:-:|---|---|---|---|
| 1 | Build | `docker build` | 이미지를 만들어 로컬에만 둡니다. | 실행 실패 |
| 2 | Tag | `docker tag` | 최종 이미지 참조를 붙입니다. | 실행 실패 |
| 3 | Gate | `orbit scan image` | 판정을 받고 결과를 `gate.json`에 저장합니다. | `0`이 아니면 |
| 4 | Push | `docker push` | 판정한 이미지를 그대로 `IMAGE`의 레지스트리에 올립니다. | 실행 실패 |
| 5 | Promote | `orbit scan promote` | push로 확정된 digest를 보고합니다. | 오류(`2`). 앞 단계가 없어 값이 없으면 건너뜀 |

- **단계는 서로 의존하지 않습니다.** 앞 단계의 출력 변수를 넘겨받지 않고, 필요한 값은 그 단계에서 직접 계산하거나 파일(`gate.json`)에서 읽습니다. 필요 없는 단계는 지워도 됩니다. 단, Build·Tag는 판정할 이미지를 만드는 단계라 Gate·Push·Promote를 쓰는 동안 남겨 둡니다. Tekton의 예외는 [Tekton 예제](tekton)에 있습니다.
- **시연 이미지에는 Critical 취약점이 있습니다.** 조직 정책이 차단으로 되어 있으면 Gate에서 멈추고 Push·Promote까지 가지 않습니다. 전체 흐름을 보려면 시연용 조직에서 차단을 사용하지 않도록 설정합니다. 이때 종료 코드는 `0`이고 `GATE` 줄에 "위반이 있으나 조직 설정으로 차단하지 않았다"가 표시됩니다.
- 자기 프로젝트에 붙일 때는 "여기만 바꿉니다" 블록을 채우고, 필요하면 Build의 빌드 대상만 자기 Dockerfile 위치로 바꿉니다.

### CLI 시험

| 순서 | 명령 | 하는 일 | 실패로 표시되는 경우 |
|:-:|---|---|---|
| 1 | `orbit version` | CLI와 SBOM 생성 엔진의 버전을 출력합니다. 서버에 접속하지 않습니다. | 실행 실패 |
| 2 | `orbit doctor` | 자격과 빌드 좌표를 점검합니다. 서버에 접속하지 않습니다. | 오류(`2`) |
| 3 | `orbit scan file` | 빌드 산출물(`SCAN_TARGET`, 기본값 `vendor/commons-text-1.9.jar`)의 판정을 받아 `gate.json`에 저장합니다. | `0`이 아니면. 차단(`1`)과 오류(`2`)는 출력으로 구분 |

- 명령마다 따로 실행되어, 하나가 실패해도 나머지는 실행됩니다.
- `scan file`은 이미지 좌표를 얻지 못합니다. 매뉴얼에 따라 용도는 빌드 시점 판정이며, 배포 이후 추적은 적용 템플릿의 `scan image`와 `scan promote`가 맡습니다.

## 모든 예제에 공통인 원칙

1. **빌드는 push 없이 합니다.** 판정 전에 레지스트리에 올라가면 게이트의 의미가 없습니다.
2. **판정 전에 최종 이미지 참조로 태그합니다.** 하지 않으면 이미지 좌표가 `docker.io/library/…:candidate`로 남습니다.
3. **판정한 이미지를 그대로 push합니다.** 다시 빌드해서 올리면 digest가 어긋납니다.
4. **종료 코드가 `0`이 아니면 중단합니다.** 차단(`1`)뿐 아니라 오류(`2`)도 통과가 아닙니다.
5. **CI 환경변수를 컨테이너에 `-e`로 넘깁니다.** CLI 컨테이너는 CI 러너의 환경변수를 물려받지 않아서, 넘기지 않으면 빌드 좌표를 자동으로 얻지 못합니다.
6. **`--pipeline-ref`는 실행마다 달라지지 않는 값으로 고정합니다.** 자동 인식 대상이 아닌 도구(Tekton, 기타 CI)에서만 직접 지정합니다. 실행마다 바뀌는 값(커밋, 빌드 번호)은 `--ci-run-id`에 넣습니다.
7. **도커 소켓 그룹 ID는 데몬 호스트 기준으로 잽니다.** 그래서 샘플은 셸에서 `stat`하지 않고 컨테이너를 띄워 잽니다. dind나 Docker Desktop에서는 셸이 있는 곳과 데몬 호스트가 달라 값이 어긋납니다. GitHub Actions 샘플은 호스티드 러너 기준이라 셸에서 바로 잽니다.
8. **rootless Docker나 podman은 소켓 경로가 달라 이 샘플을 그대로 쓸 수 없습니다.** podman 구성은 [Tekton 예제](tekton)를 참고합니다.

## 종료 코드

| 코드 | 의미 | 파이프라인 동작 |
|:-:|---|---|
| `0` | 통과 | 다음 단계로 진행합니다. |
| `1` | 게이트 위반으로 차단 | 단계를 실패시키고 이후 단계를 건너뜁니다. |
| `2` | 오류(인증, 네트워크, 시간 초과 등) | 단계를 실패시키고 이후 단계를 건너뜁니다. |

`0`에는 위반이 없는 경우와, 위반은 있지만 조직 설정에서 차단을 사용하지 않는 경우가 모두 들어 있습니다. 출력의 `GATE` 줄로 구분합니다.

## 문제가 생기면

먼저 dry-run의 `orbit doctor`를 실행합니다. 서버에 접속하지 않고, 빌드 좌표와 자격이 어떻게 해석되는지만 보여 줍니다. 도구별 실행 방법은 각 폴더 `README.md`의 "1단계"에 있습니다.

## 예제 검증 상태

| 도구 | 검증 상태 |
|---|---|
| Jenkins | TBD |
| GitLab CI | TBD |
| GitHub Actions | TBD |
| Tekton Pipelines | TBD |
| 기타 CI | TBD |

> 샘플은 Orbit CLI 2.0.1 기준으로 작성했습니다. 사용하는 CI 환경에 맞춰 이미지 이름, 변수 이름, 러너 구성을 조정하고, 운영 파이프라인에 적용하기 전에 테스트 파이프라인에서 먼저 확인하십시오.

## 문의

제품 사용과 연동 문의는 support@oliveworks.io로 보내 주십시오.

## 라이선스

Copyright 2026 OliveWorks Inc.

이 저장소의 예제는 [Apache License 2.0](LICENSE)에 따라 사용할 수 있습니다.

Orbit CLI 컨테이너 이미지(`ghcr.io/oliveworks-io/orbit-cli`)와 Orbit Security 제품의 사용 조건은 이 저장소의 라이선스와 별개입니다.
