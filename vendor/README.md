# vendor

데모 이미지(`orbit-gate-hello`, 루트 [`Dockerfile`](../Dockerfile))에 넣는 파일입니다.

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `commons-text-1.9.jar` | Maven Central `org.apache.commons:commons-text:1.9` (SHA-1 `ba6ac8c2807490944a0a27f6f8e68fb5ed2e80e2`) | Apache License 2.0. 원본 `LICENSE.txt`, `NOTICE.txt`가 JAR 안 `META-INF/`에 들어 있습니다. |

> [!IMPORTANT]
> 이 JAR에는 알려진 취약점(CVE-2022-42889)이 **의도적으로** 남아 있습니다. 빌드 게이트가 "들어 있지만 실행되지 않는 의존성"을 어떻게 판정하는지 보여 주기 위한 것입니다. 이미지에는 JRE가 없어 이 라이브러리를 실행하는 경로가 없습니다.
>
> 이 파일을 다른 프로젝트에 가져다 쓰지 마십시오. 이 파일에 대한 취약점 신고는 필요하지 않습니다.
