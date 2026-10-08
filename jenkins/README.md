# Jenkins 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

Declarative Pipeline에 Orbit CLI 빌드 게이트를 붙이는 예제입니다. 파일은 두 개이고, 순서대로 씁니다.

| 순서 | 파일 | 용도 |
|:-:|---|---|
| 1 | [`Jenkinsfile.cli-test`](Jenkinsfile.cli-test) | **dry-run.** 이미지를 만들거나 올리지 않고 `version`, `doctor`, `scan file`로 자격·네트워크·서버 판정이 통하는지 확인합니다. |
| 2 | [`Jenkinsfile`](Jenkinsfile) | **본적용 템플릿.** 자기 파이프라인에 복사해 씁니다. 이미지를 판정하고(`scan image`), 올린 뒤 확정 digest를 보고합니다(`scan promote`). |
| 2 (시연) | [`Jenkinsfile.default`](Jenkinsfile.default) | `Jenkinsfile`과 같고, 입력 블록을 ttl.sh 시연 값(`IMAGE=ttl.sh/orbit/orbit-gate-hello-default`, `IMAGE_TAG=1h`, `REGISTRY_CREDENTIALS_ID=none`)으로 미리 채운 파일입니다. 가입 없이 이 저장소를 바로 시연할 때 씁니다. ttl.sh에 올린 이미지는 누구나 받을 수 있습니다. |

공통 사전 준비(CI 인증 키, CLI 이미지 digest, 레지스트리)와 공통 원칙은 [저장소 README](../README.md)에 있습니다.

## 사전 준비

### 자격 등록

`Manage Jenkins` > `Credentials` > 대상 도메인 > `Add Credentials`에서 등록합니다.

| ID | Kind | 값 | 필요한 파일 |
|---|---|---|---|
| `orbit-client-id` | **Secret text** | CI 인증 키의 client_id | 둘 다 |
| `orbit-client-secret` | **Secret text** | CI 인증 키의 client_secret | 둘 다 |
| 원하는 ID | **Username with password** | 레지스트리 사용자 이름, 액세스 토큰 | `Jenkinsfile`, 로그인이 필요한 레지스트리만 |
| `orbit-address` | **Secret text** | 서버(pipelinegate) 주소. 예: `https://gate.<설치 도메인>` | 둘 다, 설치형(폐쇄망)만 |
| `orbit-issuer` | **Secret text** | 인증 서버(Keycloak realm) 주소. 예: `https://sso.<설치 도메인>/realms/<realm 이름>` | 둘 다, 설치형(폐쇄망)만 |

> Orbit 자격 두 개는 반드시 `Secret text`로 등록합니다. Username/Password로 등록하면 `credentials()`가 `_USR`, `_PSW` 접미 변수를 만들어 변수 이름이 어긋납니다. 레지스트리 자격은 그 ID를 `Jenkinsfile`의 `REGISTRY_CREDENTIALS_ID`에 적으면 Push 단계에서만 `withCredentials`로 꺼내 씁니다.

### 설치형(폐쇄망) 서버 주소

SaaS는 서버 주소가 CLI 이미지에 들어 있어 아무것도 등록하지 않습니다. 설치형은 위 표의 `orbit-address`, `orbit-issuer`를 등록합니다.

- 두 파일 모두 서버에 접속하는 stage(`scan image`, `scan promote`, `doctor`, `scan file`)에서 이 두 Credentials를 찾습니다.
  - **둘 다 있으면** 그 값을 `ORBIT_ADDRESS`, `ORBIT_ISSUER`로 CLI에 넘깁니다. `withCredentials`로 꺼내므로 콘솔 로그에서 `****`로 가려져, 내부 주소가 로그에 남지 않습니다.
  - **둘 다 없으면** 아무것도 넘기지 않고 CLI 이미지의 기본값(SaaS)을 씁니다. 빈 값을 넘기면 기본값을 덮어쓰기 때문에 넘기지 않습니다.
  - **하나만 있으면** 서버와 인증 서버가 다른 환경을 가리킬 수 있어 멈춥니다.
- 다른 ID로 등록했다면 `environment`의 `ORBIT_ADDRESS_CREDENTIALS_ID`, `ORBIT_ISSUER_CREDENTIALS_ID`를 그 ID로 바꿉니다.
- 값은 `http://` 또는 `https://`로 시작해야 합니다. 스킴이 없으면 CLI가 SBOM을 만들기 전에 거부합니다.
- 로그 첫머리의 `Orbit 서버: Credentials의 주소를 씁니다` 또는 `… 기본값(SaaS)을 씁니다`로 어느 쪽이 쓰였는지 확인합니다.

### 에이전트 조건

두 파일 모두 **Kubernetes Pod** 에이전트(`jnlp` + `docker:27-dind`)를 씁니다.

- **필요한 것:** Jenkins Kubernetes 플러그인, Pod를 띄울 클라우드 설정, 그 네임스페이스에서 **privileged** 컨테이너 허용
- 모든 stage는 `dind` 컨테이너 안에서 돌고, 시작할 때 dockerd가 뜰 때까지 기다립니다. stage끼리 의존하지 않도록 stage마다 기다립니다.
- 빌드, 판정, push가 모두 `dind` 컨테이너의 dockerd에서 일어납니다. 판정 단계가 마운트하는 `/var/run/docker.sock`도 이 dockerd의 소켓입니다.
- `dind` 컨테이너는 메모리 요청 512Mi, 한도 3Gi입니다. CLI(SBOM 생성 엔진 Trivy)가 이 컨테이너 안에서 돌기 때문에 한도를 크게 잡았습니다. 빌드할 이미지가 크면 늘립니다.
- 파이프라인 전체 시간 한도는 20분입니다(`options { timeout(...) }`).
- Kubernetes가 없고 Docker가 있는 일반 에이전트에서 돌리려면 `agent`를 `any`로 바꾸고 각 stage의 `container('dind') { … }` 블록을 걷어 냅니다.
- CLI 이미지를 내려받을 수 있어야 합니다. 폐쇄망이면 내부 레지스트리에 미러링합니다. TBD

## 1단계: dry-run (`Jenkinsfile.cli-test`)

Orbit 자격 두 개만 있으면 됩니다. 이미지를 만들거나 올리지 않으므로 레지스트리 자격은 필요 없습니다.

1. 이 저장소를 소스로 하는 Pipeline 잡을 만듭니다(Pipeline script from SCM, Script Path `jenkins/Jenkinsfile.cli-test`). Kubernetes 클라우드가 설정되어 있어야 합니다(위 "에이전트 조건").
2. 그대로 실행합니다. 판정 대상은 `SCAN_TARGET`(기본값 `vendor/commons-text-1.9.jar`)입니다.

| stage | 하는 일 |
|---|---|
| orbit version | CLI와 SBOM 생성 엔진의 버전을 출력합니다. |
| orbit doctor | 자격과 빌드 좌표를 점검합니다. 오류(`2`)면 실패로 표시합니다. |
| orbit scan file | `SCAN_TARGET`의 판정을 받아 `gate.json`에 저장합니다. `0`이 아니면 실패로 표시합니다. |

- stage마다 `catchError`로 감싸 하나가 실패해도 다음 stage를 실행합니다. 빌드 결과는 실패로 남습니다.
- 모든 stage는 `dind` 컨테이너 안에서 돌고, 시작할 때 dockerd가 뜰 때까지 기다립니다. stage끼리 의존하지 않도록 stage마다 기다립니다.
- 기본 대상 JAR에는 Critical 취약점이 있어 조직 정책에 따라 차단(`1`)이 나올 수 있습니다. 판정이 돌아왔다는 점에서 dry-run으로는 정상입니다. 오류(`2`)면 자격이나 네트워크를 먼저 확인합니다.
- `scan file` 대상은 JAR, Go·Rust 바이너리, rootfs 디렉터리 등 빌드 산출물입니다. 소스 트리를 주면 분석된 패키지가 0개라 종료 코드 `2`로 실패합니다.
- 산출물은 임시 폴더에 담아 `docker cp`로 CLI 컨테이너에 넣습니다. CLI는 비루트(65532)로 돌기 때문에 폴더에 읽기 권한을 줍니다.

## 2단계: 본적용 (`Jenkinsfile`)

1. [`Jenkinsfile`](Jenkinsfile)을 자기 저장소에 복사합니다. 이 저장소로 시연할 때는 Script Path를 `jenkins/Jenkinsfile`로 한 잡을 만듭니다.
2. `environment` 맨 위 "여기만 바꿉니다" 블록을 채웁니다. 자리표시(`<…>`)가 남아 있으면 해당 단계에서 무엇을 넣어야 하는지 알려 주고 멈춥니다.

   | 변수 | 값 | 채우지 않으면 |
   |---|---|---|
   | `IMAGE` | 판정하고 올릴 이미지. 예: `registry.example.com/team/myapp` | Tag에서 멈춤 |
   | `IMAGE_TAG` | 태그. 비우면 커밋 해시 | 커밋 해시 사용 |
   | `REGISTRY_CREDENTIALS_ID` | 레지스트리 자격의 Credentials ID, 또는 로그인하지 않으려면 `none` | Push에서 멈춤 |

   가입 없이 시연할 때는 `IMAGE=ttl.sh/orbit/orbit-gate-hello-<임의 문자열>`, `IMAGE_TAG=1h`, `REGISTRY_CREDENTIALS_ID=none`입니다. ttl.sh에 올린 이미지는 누구나 받을 수 있습니다.
3. 자기 프로젝트라면 Build 단계의 빌드 대상(`docker build … .`)을 자기 Dockerfile에 맞춥니다.
4. 파이프라인을 실행합니다.

| stage | 하는 일 |
|---|---|
| Build | 이미지를 만들어 로컬에만 둡니다(push하지 않음). |
| Tag | 최종 이미지 참조(`IMAGE:IMAGE_TAG`, 태그를 비우면 커밋 해시)를 붙입니다. `IMAGE`를 채우지 않았으면 멈춥니다. |
| Orbit Security (scan image) | 이미지를 스캔해 판정을 받고 `gate.json`에 저장합니다. 종료 코드가 `0`이 아니면 `error()`로 중단합니다. |
| Push | 판정한 이미지를 그대로 올립니다. `REGISTRY_CREDENTIALS_ID`가 `none`이면 로그인하지 않습니다. |
| Orbit Promote (scan promote) | `gate.json`의 requestId와 push된 digest를 보고합니다. 값이 없으면 건너뜁니다. |

`gate.json`은 결과와 관계없이 빌드 아티팩트로 보관합니다. 단계는 서로의 결과 변수에 기대지 않아 필요 없는 stage는 지워도 됩니다(Build·Tag는 남겨 둡니다).

### 지켜야 할 것

1. **빌드는 push 없이** 합니다. 판정 전에 올라가면 게이트의 의미가 없습니다.
2. **판정 전에 최종 참조로 태그**합니다. 하지 않으면 이미지 좌표가 `docker.io/library/…:candidate`로 남습니다.
3. **`returnStatus: true`를 씁니다.** 쓰지 않으면 `sh`가 차단(exit 1)에서 바로 죽어 결과를 볼 수 없습니다.
4. **`0`이 아니면 `error()`로 중단**합니다. `2`(오류)도 통과가 아닙니다.

## 동작 확인

파이프라인을 한 번 실행하고 `gate.json`에서 확인합니다.

| 확인할 것 | 정상 |
|---|---|
| `pipelineRef` | `jenkins.example.com/myapp-release`처럼 Jenkins 주소와 잡 이름으로 시작합니다. `system:`으로 시작하면 실패입니다. |
| `sourceRef` | `GIT_URL`이 있어야 채워집니다. |
| `image` | 본적용에서는 `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. dry-run의 `scan file`은 비어 있는 것이 정상입니다. |

> `GIT_URL`, `GIT_COMMIT`은 `checkout scm` 없이 수동으로 `git`을 호출하는 파이프라인에서는 주입되지 않을 수 있습니다.

## 문제 해결

먼저 dry-run(`Jenkinsfile.cli-test`)의 `orbit doctor` 결과를 봅니다. 서버에 접속하지 않고 좌표와 자격 해석 결과만 보여 줍니다.

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `-e JENKINS_URL`, `-e JOB_NAME`이 빠졌습니다. |
| `sourceRef`가 비어 있음 | `checkout scm`을 쓰거나 `--source-ref`를 지정합니다. |
| 자격 변수에 `_USR`, `_PSW`가 붙음 | Orbit 자격의 Credentials 유형을 `Secret text`로 바꿉니다. |
| Pod가 만들어지지 않음 | 네임스페이스의 Pod Security 정책이 privileged 컨테이너를 막고 있을 수 있습니다. Kubernetes 클라우드 설정과 네임스페이스 정책을 확인합니다. |
| stage가 시작 직후 멈춰 있다가 20분 뒤 실패 | dockerd가 뜨지 않아 기동 대기에서 멈춘 것입니다. `dind` 컨테이너 로그에서 privileged 거부나 메모리 부족을 확인합니다. |
| `ORBIT_ADDRESS와 ORBIT_ISSUER Credentials는 둘 다 등록하거나 둘 다 지웁니다`로 멈춤 | 두 Credentials 중 하나만 있습니다. 나머지도 등록하거나 둘 다 지웁니다. |
| 설치형인데 `토큰 엔드포인트에 도달하지 못했다` | Credentials가 없어 SaaS 주소로 접속했을 수 있습니다. 로그의 `Orbit 서버:` 줄과 Credentials ID를 확인합니다. |
| `IMAGE를 설정하십시오`로 멈춤 | `environment`의 `IMAGE`를 채웁니다. |
| `REGISTRY_CREDENTIALS_ID를 정하십시오`로 멈춤 | Credentials ID 또는 `none`을 적습니다. |
| 차단인데 단계가 그냥 실패함 | `returnStatus: true`가 빠졌습니다. |
| `분석된 패키지가 0개다`로 중단됨(`2`) | 대상에서 패키지를 찾지 못했습니다. 빌드 산출물이 이미지(dry-run은 `SCAN_TARGET`)에 들어 있는지 확인합니다. 빈 SBOM은 통과시키지 않습니다. |
| Promote에서 `409` | 판정한 이미지와 push한 이미지가 다릅니다. 다시 빌드해서 올리지 않았는지 확인합니다. |

## 다음 단계

- Kaniko 등 privileged 없이 빌드하는 구성: TBD
- 폐쇄망 서버 주소: 위 "설치형(폐쇄망) 서버 주소". 공통 설명은 [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
