import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ⚠️ 패키지를 이름만으로 지정하면 이 설정 파일 위치(.config/stylelint/) 기준으로 찾게 되어
//   전역 npm 패키지 폴더의 패키지를 찾지 못하고 실패합니다. CSS 설정(stylelint.config.mjs)과
//   같은 방식으로 전역 npm 패키지 경로에서 직접 해석합니다.
const globalNodeModules = path.join(__dirname, '../../data/.npm-packages/lib/node_modules');
// stylelint-config-*-scss 는 ESM 전용 패키지("exports"에 import 조건만 있음)라 require.resolve 로는
// 찾지 못합니다(ERR_PACKAGE_PATH_NOT_EXPORTED, 실측). 그 경우 package.json 의 exports 를 직접 읽어
// 진입 파일 경로를 만듭니다.
const resolve = (name) => {
  try {
    return require.resolve(name, { paths: [globalNodeModules] });
  } catch {
    const [pkgName, ...sub] = name.split('/');
    const pkgDir = path.join(globalNodeModules, pkgName);
    const pkg = JSON.parse(readFileSync(path.join(pkgDir, 'package.json'), 'utf8'));
    const key = sub.length > 0 ? `./${sub.join('/')}` : '.';
    let entry = pkg.exports && typeof pkg.exports === 'object' && key in pkg.exports ? pkg.exports[key] : undefined;
    if (entry === undefined && key === '.') {
      entry = pkg.exports;
    }
    while (entry && typeof entry === 'object') {
      entry = entry.import || entry.default;
    }
    return path.join(pkgDir, typeof entry === 'string' ? entry : pkg.main || 'index.js');
  }
};

/**
 * SCSS를 포함한 Stylelint 설정을 정의
 * @type {import('stylelint').Config}
 */
const config = {
  // Stylelint가 SCSS 문법을 올바르게 파싱하도록 설정
  customSyntax: resolve('postcss-scss'),

  // 플러그인 설정
  plugins: [
    resolve('stylelint-prettier') // Prettier와의 통합을 위한 플러그인
  ],

  // SCSS 환경에 최적화된 표준 규칙 세트를 상속받아 사용
  extends: [
    resolve('stylelint-config-recommended-scss'), // CSS + SCSS 문제 방지
    resolve('stylelint-config-standard-scss'), // 최신 SCSS 표준 (CSS 규칙도 포함)

    /*
     * Prettier와 충돌 방지를 위해 반드시 마지막에 위치해야 함
     * ※ stylelint-config-prettier-scss 는 넣지 않습니다: Stylelint 15 부터 포맷팅 규칙이 제거되어
     *   끌 규칙이 없으므로 결과가 완전히 같습니다(실측: 있을 때와 없을 때 검사 결과 동일).
     */
    resolve('stylelint-prettier/recommended') // Prettier를 lint 규칙으로도 사용
  ],

  /**
   * 사용자 규칙 정의
   * - 각 규칙에 대한 자세한 내용은 Stylelint 공식 문서 참고: https://stylelint.io/user-guide/rules/list
   * - 다음과 같이 설정 값과 옵션을 함께 지정 가능하다(옵션에는 severity(심각도) 설정을 포함할 수 있음).
   *   예) '규칙 이름': [설정 값, { 옵션 }] → 'selector-max-id': [0, {severity: 'warning'}]
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

    // ----------------------------------------------------
    // 1. 일반 CSS/Stylelint 규칙 재정의
    // ----------------------------------------------------

    // ID 선택자 사용 금지 (선택 사항: 클래스 기반 사용을 권장할 때) → 0: ID 선택자 사용 금지(권장), 1: 선택자에서 ID 최대 1개 허용
    'selector-max-id': [0, {severity: 'warning'}],

    // ----------------------------------------------------
    // 2. SCSS 관련 규칙 추가/재정의 (stylelint-config-standard-scss에 의해 일부 기본 적용됨)
    // ----------------------------------------------------

    // 클래스 선택자 패턴 설정 → '^[a-z][a-z0-9-]+$': Kebab-Case 강제, '^[a-z][a-zA-Z0-9]+$': CamelCase 강제
    'selector-class-pattern': '^[a-z][a-z0-9-]+$',

    // CSS 모듈이나 컴포넌트 환경에서 많이 사용하는, 최대 중첩 레벨 제한 (선택 사항)
    'scss/selector-no-redundant-nesting-selector': true, // & 기호를 중복하여 중첩하는 것을 방지
    'max-nesting-depth': 3 // 최대 3단계까지만 중첩 허용 (너무 깊은 중첩 방지)

    // @import 대신 @use나 @forward 사용을 권장하는 경우 (선택 사항: Sass 모듈 시스템 사용 시)
    // 'scss/at-import-partial-extension': 'always',
  },
  overrides: [
    {
      files: ['**/*.css'],
      customSyntax: 'postcss'
    }
  ]
};

export default config;
