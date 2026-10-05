# GitLab CI 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

`.gitlab-ci.yml`의 빌드 잡에 Orbit CLI 빌드 게이트를 붙이는 예제입니다. 파이프라인을 새로 만들 필요는 없고, 빌드 잡에 **게이트와 push 단계**를 끼워 넣습니다.

- 샘플 파일: [`.gitlab-ci.yml`](.gitlab-ci.yml)
- 공통 사전 준비(CI 인증 키, CLI 이미지 digest, 공통 원칙)는 [저장소 README](../README.md)를 먼저 읽습니다.

## 사전 준비

### 자격 두 개 등록

`Settings` > `CI/CD` > `Variables` > `Add variable`에서 두 개를 등록합니다.

| 이름 | 값 | 옵션 |
|---|---|---|
| `ORBIT_CLIENT_ID` | CI 인증 키의 client_id | 없음 |
| `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret | **Masked** |

> `Protected`를 켜면 보호된 브랜치와 태그에서만 변수가 주입됩니다. 기능 브랜치에서도 게이트를 돌리려면 `Protected`를 켜지 않습니다. 켠 상태에서 보호되지 않은 브랜치에서 실행하면 자격이 없어 오류(`2`)로 끝납니다.

### 러너 조건

- Docker를 쓸 수 있는 러너가 필요합니다. 샘플은 `docker:dind` 서비스를 쓰는 구성이고, 소켓을 마운트하는 러너라면 `services`와 `DOCKER_*` 변수를 삭제합니다.
- CLI 이미지를 내려받을 수 있어야 합니다. 폐쇄망이면 내부 레지스트리에 미러링합니다. TBD

## 샘플 사용법

1. [`.gitlab-ci.yml`](.gitlab-ci.yml)의 `variables`에서 `ORBIT_CLI_IMAGE`의 `<64자 hex>`에 확인한 digest를 넣습니다.
2. 기존 빌드 잡의 `script`를 샘플의 순서(빌드, 태그, 판정, 중단 확인, push, 선택 보고)로 맞춥니다.
3. 파이프라인을 실행합니다.

### 단계 설명

| 순서 | 하는 일 |
|:-:|---|
| 1 | 이미지를 만들어 로컬에만 둡니다(push하지 않음). |
| 2 | 최종 이미지 참조(`$CI_REGISTRY_IMAGE:커밋`)를 붙입니다. |
| 3 | 이미지를 스캔해 판정을 받고 결과를 `gate.json`에 저장합니다. |
| 4 | 종료 코드가 `0`이 아니면 잡을 실패시킵니다. |
| 5 | 판정을 통과한 이미지를 그대로 push합니다. |
| 6 | 선택. 확정 digest를 서버에 보고해 런타임 이미지와 연결합니다. |

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
| `image` | `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. |
| 잡 결과 | 통과면 성공, 차단이면 잡이 실패합니다. |

## 문제 해결

먼저 `orbit doctor`를 실행합니다.

```sh
docker run --rm \
  -e CI_SERVER_HOST -e CI_PROJECT_PATH -e CI_CONFIG_PATH \
  -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET \
  "$ORBIT_CLI_IMAGE" doctor
```

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `-e CI_SERVER_HOST`, `-e CI_CONFIG_PATH`가 빠졌습니다. |
| `pipelineRef is not canonical`(`400`) | `--pipeline-ref`를 직접 주었습니다. 빼십시오. |
| `stat: /var/run/docker.sock` 실패 | 그룹 ID를 컨테이너를 띄워서 측정합니다(샘플 3번 단계). |
| 두 번째 잡에서 이미지를 못 찾음 | 빌드와 게이트를 한 잡에 둡니다. |
| 기능 브랜치에서만 오류(`2`) | `ORBIT_CLIENT_SECRET`의 `Protected`를 끕니다. |
| 취약점 0건으로 통과 | SBOM이 비었을 수 있습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. |

## 다음 단계

- 멀티 아키텍처: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
