/* ============================================================
   Supabase 접속 정보
   Supabase 콘솔 → Project Settings → API 에서 두 값을 복사해
   아래 따옴표 안에 붙여넣으세요.

   anon key는 공개돼도 되는 값입니다. 실제 접근 통제는
   데이터베이스의 RLS 정책이 담당합니다. (sql/01_schema.sql 참고)
   반대로 service_role key는 절대 여기 넣지 마세요.
   ============================================================ */

window.CONFIG = {
  SUPABASE_URL:      "https://여기에-프로젝트-주소.supabase.co",
  SUPABASE_ANON_KEY: "여기에-anon-public-key"
};
