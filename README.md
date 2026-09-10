# 판촉물 관리대장

사내 판촉물 재고와 배포 이력을 관리하는 웹 앱입니다.
가입 → 관리자 승인 → 사용 신청 → 재고 자동 차감 순으로 동작합니다.

빌드 도구가 필요 없습니다. 정적 파일 몇 개가 전부입니다.

```
index.html            앱 전체 (화면 + 로직)
config.js             Supabase 접속 정보  ← 여기만 직접 채웁니다
config.example.js     config.js 견본
manifest.webmanifest  홈 화면 추가(PWA) 설정
icon.svg              앱 아이콘
sql/01_schema.sql     테이블 · 권한 정책 · 저장소 설정
```

---

## 1. Supabase 준비

1. [supabase.com](https://supabase.com) 가입 후 **New project**
   **리전은 반드시 Northeast Asia (Seoul)** 로 선택하세요. 생성 후에는 바꿀 수 없습니다.
2. 왼쪽 메뉴 **SQL Editor → New query** 에 `sql/01_schema.sql` 전체를 붙여넣고 **Run**
3. **Authentication → Providers → Email**
   - Confirm email 켜기 (본인 메일 인증)
   - 회사 도메인만 가입되도록 허용 도메인 설정
4. **Project Settings → API** 에서 두 값을 복사
   - `Project URL`
   - `anon` `public` key

`anon key`는 공개돼도 되는 값입니다. 실제 차단은 데이터베이스의 RLS 정책이 합니다.
**`service_role` key는 절대 이 저장소에 넣지 마세요.**

## 2. 접속 정보 입력

`config.js` 를 열어 위에서 복사한 두 값을 넣습니다.

```js
window.CONFIG = {
  SUPABASE_URL:      "https://xxxxx.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOi..."
};
```

## 3. GitHub에 올리기

**웹으로 하는 방법** (터미널 없이)

1. GitHub 가입 → **New repository** → 이름 `promo-app`, **Private** 선택
2. 생성된 화면에서 **uploading an existing file** 클릭
3. 이 폴더의 파일을 전부 끌어다 놓고 **Commit changes**

**터미널로 하는 방법**

```bash
git init
git add .
git commit -m "판촉물 관리대장 최초 등록"
git branch -M main
git remote add origin https://github.com/<계정>/promo-app.git
git push -u origin main
```

## 4. 웹에 올리기

**Vercel** — [vercel.com](https://vercel.com) 에 GitHub 계정으로 로그인 →
**Add New → Project** → 저장소 선택 → Framework Preset은 **Other** → **Deploy**.
빌드 설정은 건드릴 필요가 없습니다. 1분 안에 `https://promo-app.vercel.app` 같은 주소가 나옵니다.

이후 GitHub에 파일을 수정해 올릴 때마다 자동으로 다시 배포됩니다.

회사 도메인을 붙이려면 Vercel의 **Settings → Domains** 에서 등록하고,
IT부서에 DNS 레코드 추가를 요청하면 됩니다.

## 5. 첫 관리자 지정

아무도 관리자가 아닌 상태에서는 승인해줄 사람이 없으므로, 최초 1회만 SQL로 처리합니다.

1. 배포된 주소에서 본인 이메일로 **가입 신청**
2. 메일 인증 완료
3. Supabase **SQL Editor** 에서 실행

```sql
update public.profiles
   set role = 'admin', status = 'approved', approved_at = now()
 where email = '본인이메일@회사.com';
```

이후로는 화면에서 승인과 권한 변경이 됩니다.
**관리자는 최소 2명** 두세요. 승인해줄 사람이 자리를 비우면 신규 인원이 며칠씩 들어오지 못합니다.

## 6. 앱처럼 쓰기

배포된 주소를 휴대폰에서 열고 브라우저 메뉴의 **홈 화면에 추가**를 누르면
아이콘이 생기고 주소창 없이 실행됩니다. 앱스토어 심사가 필요 없습니다.

---

## 운영 메모

- **퇴직·전배자**는 계정을 삭제하지 말고 화면에서 **사용 중지**로 바꾸세요.
  삭제하면 그 사람이 남긴 배포 이력까지 함께 사라집니다.
- **수정 가능 시간은 30분**입니다. 이후에는 관리자만 손댈 수 있습니다.
  바꾸려면 `sql/01_schema.sql` 의 `interval '30 minutes'` 를 고치고 다시 실행하세요.
- **재고 부족은 데이터베이스가 막습니다.** 화면 검사와 별개로 한 겹 더 있어서,
  두 사람이 동시에 마지막 재고를 집어도 한 명만 성공합니다.
- **백업** — Supabase 무료 플랜은 백업이 없고 일주일 미접속 시 프로젝트가 멈춥니다.
  업무용이라면 Pro 플랜을 권합니다.

## 저장되는 개인정보

이름, 회사 이메일 두 가지뿐입니다.
비밀번호는 Supabase Auth가 해시로만 보관하며 앱 데이터베이스에는 컬럼조차 없습니다.
관리자도 원본을 볼 수 없습니다.
