# GitLab CI 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

GitLab CI에 Orbit CLI 빌드 게이트를 붙이는 예제입니다. 파일은 두 개이고, 순서대로 씁니다.

| 순서 | 파일 | 용도 |
|:-:|---|---|
| 1 | [`.gitlab-ci.cli-test.yml`](.gitlab-ci.cli-test.yml) | **dry-run.** 이미지를 만들거나 올리지 않고 `version`, `doctor`, `scan file`로 자격·네트워크·서버 판정이 통하는지 확인합니다. |
| 2 | [`.gitlab-ci.yml`](.gitlab-ci.yml) | **본적용 템플릿.** 자기 프로젝트에 복사해 씁니다. 이미지를 판정하고(`scan image`), 올린 뒤 확정 digest를 보고합니다(`scan promote`). |

공통 사전 준비(CI 인증 키, CLI 이미지 digest, 레지스트리)와 공통 원칙은 [저장소 README](../README.md)에 있습니다.

## 사전 준비

### 변수 등록

`Settings` > `CI/CD` > `Variables` > `Add variable`에서 등록합니다.

| 이름 | 값 | 옵션 | 필요한 파일 |
|---|---|---|---|
| `ORBIT_CLIENT_ID` | CI 인증 키의 client_id | 없음 | 둘 다 |
| `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret | **Masked** | 둘 다 |
| `REGISTRY_USERNAME` | 레지스트리 사용자 이름 | 없음 | `.gitlab-ci.yml`, `REGISTRY_LOGIN`이 `credentials`일 때만 |
| `REGISTRY_TOKEN` | 레지스트리 액세스 토큰 | **Masked** | `.gitlab-ci.yml`, `REGISTRY_LOGIN`이 `credentials`일 때만 |
| `IMAGE`, `IMAGE_TAG`, `REGISTRY_LOGIN` | 본적용 입력값. 여기에 넣으면 파일을 고치지 않아도 됩니다. | 없음 | `.gitlab-ci.yml`(선택) |

> `Protected`를 켜면 보호된 브랜치와 태그에서만 변수가 주입됩니다. 기능 브랜치에서도 게이트를 돌리려면 `Protected`를 켜지 않습니다. 켠 상태에서 보호되지 않은 브랜치에서 실행하면 자격이 없어 오류(`2`)로 끝납니다.

### 러너 조건

- Docker를 쓸 수 있는 러너가 필요합니다. 샘플은 `docker:dind` 서비스를 쓰는 구성이고, 소켓을 마운트하는 러너라면 `services`와 `DOCKER_*` 변수를 삭제합니다.
- CLI 이미지를 내려받을 수 있어야 합니다. 폐쇄망이면 내부 레지스트리에 미러링합니다. TBD

## 1단계: dry-run (`.gitlab-ci.cli-test.yml`)

Orbit 자격 두 개만 있으면 됩니다. 이미지를 만들거나 올리지 않으므로 레지스트리 자격은 필요 없습니다.

1. 이 저장소를 GitLab 프로젝트로 가져옵니다.
2. `Settings` > `CI/CD` > `CI/CD configuration file`에 `gitlab-ci/.gitlab-ci.cli-test.yml`을 지정하고 파이프라인을 실행합니다. 판정 대상은 `SCAN_TARGET`(기본값 `vendor/commons-text-1.9.jar`)입니다.

| 잡 | 하는 일 |
|---|---|
| `orbit_version` | CLI와 SBOM 생성 엔진의 버전을 출력합니다. |
| `orbit_doctor` | 자격과 빌드 좌표를 점검합니다. 오류(`2`)면 잡이 실패합니다. |
| `orbit_scan_file` | `SCAN_TARGET`의 판정을 받아 `gate.json`에 저장합니다. `0`이 아니면 잡이 실패합니다. |

- 세 잡은 같은 stage에서 따로 실행되어, 하나가 실패해도 나머지는 실행됩니다.
- 기본 대상 JAR에는 Critical 취약점이 있어 조직 정책에 따라 차단(`1`)이 나올 수 있습니다. 판정이 돌아왔다는 점에서 dry-run으로는 정상입니다. 오류(`2`)면 자격이나 네트워크를 먼저 확인합니다.
- `scan file` 대상은 JAR, Go·Rust 바이너리, rootfs 디렉터리 등 빌드 산출물입니다. 소스 트리를 주면 분석된 패키지가 0개라 종료 코드 `2`로 실패합니다.
- dind에서는 잡의 작업 폴더를 마운트할 수 없어, 산출물을 임시 폴더에 담아 `docker cp`로 CLI 컨테이너에 넣습니다. CLI는 비루트(65532)로 돌기 때문에 폴더에 읽기 권한을 줍니다.

## 2단계: 본적용 (`.gitlab-ci.yml`)

1. [`.gitlab-ci.yml`](.gitlab-ci.yml)을 자기 프로젝트 루트에 복사합니다. 이 저장소로 시연할 때는 `CI/CD configuration file`을 `gitlab-ci/.gitlab-ci.yml`로 바꿉니다.
2. 입력값을 정합니다. 같은 이름의 CI/CD 변수로 넣거나, `variables` 맨 위 "여기만 바꿉니다" 블록을 고칩니다. 자리표시(`<…>`)가 남아 있으면 해당 항목에서 무엇을 넣어야 하는지 알려 주고 멈춥니다.

   | 변수 | 값 | 채우지 않으면 |
   |---|---|---|
   | `IMAGE` | 판정하고 올릴 이미지. 예: `registry.example.com/team/myapp`, GitLab 레지스트리는 `$CI_REGISTRY_IMAGE` | 태그 항목에서 멈춤 |
   | `IMAGE_TAG` | 태그. 비우면 커밋 해시 | 커밋 해시 사용 |
   | `REGISTRY_LOGIN` | `credentials`(자격으로 로그인) 또는 `none`(로그인하지 않음) | push 항목에서 멈춤 |

   가입 없이 시연할 때는 `IMAGE=ttl.sh/orbit/orbit-gate-hello-<임의 문자열>`, `IMAGE_TAG=1h`, `REGISTRY_LOGIN=none`입니다. ttl.sh에 올린 이미지는 누구나 받을 수 있습니다.
3. 자기 프로젝트라면 빌드 항목의 빌드 대상(`docker build … .`)을 자기 Dockerfile에 맞춥니다.
4. 파이프라인을 실행합니다.

| 순서 | 하는 일 |
|:-:|---|
| 1 | 이미지를 만들어 로컬에만 둡니다(push하지 않음). |
| 2 | 최종 이미지 참조(`IMAGE:IMAGE_TAG`, 태그를 비우면 커밋 해시)를 붙입니다. `IMAGE`를 채우지 않았으면 멈춥니다. |
| 3 | 이미지를 스캔해 판정을 받고 `gate.json`에 저장합니다. 종료 코드가 `0`이 아니면 잡을 실패시킵니다. |
| 4 | 판정한 이미지를 그대로 올립니다. `REGISTRY_LOGIN`이 `credentials`면 로그인합니다. |
| 5 | `gate.json`의 requestId와 push된 digest를 보고합니다. 값이 없으면 건너뜁니다. |

`gate.json`은 결과와 관계없이 잡 아티팩트로 보관합니다. 항목은 서로의 결과 변수에 기대지 않아 필요 없는 항목은 지워도 됩니다(빌드·태그는 남겨 둡니다).

### 지켜야 할 것

1. **빌드와 게이트를 한 잡에** 둡니다. dind 서비스는 잡 단위라 잡을 나누면 이미지가 사라집니다.
2. **판정 전에 최종 참조로 태그**합니다. 하지 않으면 이미지 좌표가 `docker.io/library/…:candidate`로 남습니다.
3. **도커 소켓 그룹 ID는 컨테이너를 띄워서 측정**합니다. 잡 컨테이너에서 `stat`을 하면 dind에서 실패합니다.
4. **`0`이 아니면 중단**합니다. `2`(오류)도 통과가 아닙니다.
5. **`--pipeline-ref`를 직접 주지 않습니다.** GitLab은 자동 인식 대상입니다. 직접 만들면 서버 검증에서 `pipelineRef is not canonical`(`400`)이 납니다.

## 동작 확인

| 확인할 것 | 정상 |
|---|---|
| `pipelineRef` | `gitlab.example.com/team/myapp/.gitlab-ci.yml`처럼 GitLab 주소로 시작합니다. `system:`으로 시작하면 실패입니다. |
| `image` | 본적용에서는 `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. dry-run의 `scan file`은 비어 있는 것이 정상입니다. |
| 잡 결과 | 통과면 성공, 차단이면 잡이 실패합니다. |

## 문제 해결

먼저 dry-run(`.gitlab-ci.cli-test.yml`)의 `orbit_doctor` 결과를 봅니다. 서버에 접속하지 않고 좌표와 자격 해석 결과만 보여 줍니다.

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `-e CI_SERVER_HOST`, `-e CI_CONFIG_PATH`가 빠졌습니다. |
| `pipelineRef is not canonical`(`400`) | `--pipeline-ref`를 직접 주었습니다. 빼십시오. |
| `IMAGE를 설정하십시오`로 멈춤 | `IMAGE`를 CI/CD 변수나 `variables`에 넣습니다. |
| `REGISTRY_LOGIN을 정하십시오`로 멈춤 | `credentials` 또는 `none`을 넣습니다. |
| `stat: /var/run/docker.sock` 실패 | 그룹 ID를 컨테이너를 띄워서 측정합니다(본적용 3번 항목). |
| 두 번째 잡에서 이미지를 못 찾음 | 빌드와 게이트를 한 잡에 둡니다. |
| 기능 브랜치에서만 오류(`2`) | `ORBIT_CLIENT_SECRET`의 `Protected`를 끕니다. |
| `분석된 패키지가 0개다`로 중단됨(`2`) | 대상에서 패키지를 찾지 못했습니다. 빌드 산출물이 이미지(dry-run은 `SCAN_TARGET`)에 들어 있는지 확인합니다. 빈 SBOM은 통과시키지 않습니다. |

## 다음 단계

- 멀티 아키텍처: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
