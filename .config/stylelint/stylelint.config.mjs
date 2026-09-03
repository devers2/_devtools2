import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const globalNodeModules =
  process.platform === 'win32'
    ? path.join(__dirname, '../../data/.npm-packages/node_modules')
    : path.join(__dirname, '../../data/.npm-packages/lib/node_modules');

/**
 * 순수 CSS 전용 Stylelint 설정을 정의 (SCSS는 stylelint.scss.config.mjs 참고)
 * @type {import('stylelint').Config}
 */
const config = {
  // 플러그인 설정 (글로벌 설치 경로를 명시적으로 resolve하여 어디서 실행하든 정상 탐색)
  plugins: [
    require.resolve('stylelint-prettier', { paths: [globalNodeModules] })
  ],

  // 표준 CSS 규칙 세트를 상속받아 사용
  extends: [
    require.resolve('stylelint-config-standard', { paths: [globalNodeModules] }),
    require.resolve('stylelint-prettier/recommended', { paths: [globalNodeModules] })
  ],

  /**
   * 사용자 규칙 정의
   * - 각 규칙에 대한 자세한 내용은 Stylelint 공식 문서 참고: https://stylelint.io/user-guide/rules/list
   * - 다음과 같이 설정 값과 옵션을 함께 지정 가능하다(옵션에는 severity(심각도) 설정을 포함할 수 있음).
   *   예) '규칙 이름': [설정 값, { 옵션 }] → 'selector-max-id': [0, { severity: 'warning' }]
   *   ※ severity 옵션 값 → 'error': 오류 (기본값), 'warning': 경고, null: 무시
   */
  rules: {
    'prettier/prettier': [
      // Prettier 규칙을 Stylelint 규칙으로 활성화
      true,
      // 필요시 Prettier 규칙 재정의
      {
        singleQuote: true // 작은 따옴표 사용 → true: 작은 따옴표 사용, false: 큰 따옴표 사용(기본값)
      }
    ],

    // ID 선택자 사용 금지 (선택 사항: 클래스 기반 사용을 권장할 때) → 0: ID 선택자 사용 금지(권장), 1: 선택자에서 ID 최대 1개 허용
    'selector-max-id': [0, { severity: 'warning' }]
  },
  overrides: [
    {
      files: ['**/*.css'],
      customSyntax: 'postcss'
    }
  ]
};

export default config;
