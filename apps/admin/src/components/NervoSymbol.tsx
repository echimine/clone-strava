/**
 * The Nervo symbol "Col" (ADR-032 §2), inline so it takes `currentColor`.
 * Same geometry as the master `packages/ui/src/brand/nervo-symbol.svg`
 * (checked by `branding.test.tsx`). Decorative: the lockup text names it.
 */
export function NervoSymbol({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 100 100" aria-hidden="true" className={className}>
      <path
        d="M24 78 L24 24 L44 50 L51 42 L76 78 L76 22"
        fill="none"
        stroke="currentColor"
        strokeWidth={10}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
