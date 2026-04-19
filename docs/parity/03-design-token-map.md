# 03 Design Token Map

## Token Map (Web `globals.css` -> iOS `Color.Brand`)

### Colors
- **primary** (Azure Blue)
  - Web: `#0080FF`
  - iOS: `Color(hex: "0080FF")`
- **primaryLight**
  - Web: `#E5F2FF`
  - iOS: `Color(hex: "E5F2FF")`
- **primaryDark**
  - Web: `#0066CC`
  - iOS: `Color(hex: "0066CC")`
- **accent** (Mint Cyan)
  - Web: `#00E5CC`
  - iOS: `Color(hex: "00E5CC")`
- **accentLight**
  - Web: `#E5FCF9`
  - iOS: `Color(hex: "E5FCF9")`
- **warning / coral**
  - Web: `#FF4D4D` (or `#F97316` via MASTER config override)
  - iOS: `Color.red` / `Color.orange` equivalent token needed.
- **paper**
  - Web: `#FDFDFC`
  - iOS: `Color(hex: "FDFDFC")`
- **background**
  - Web: `#FDFDFC` / `#F5F5F5`
  - iOS: `Color(hex: "F5F5F5")`
- **text** (ZY Ink)
  - Web: `#1B1B18`
  - iOS: `Color(hex: "1B1B18")`
- **textSecondary**
  - Web: `#6B7280`
  - iOS: `Color(hex: "6B7280")`
- **glass border**
  - Web: `rgba(255, 255, 255, 0.2)`
  - iOS: `.white.opacity(0.2)`
- **surface card**
  - Web: `#FFFFFF`
  - iOS: `.white`

### Shadow
- **shadow-md3-2**
  - Web: `0 4px 16px rgba(0, 0, 0, 0.06)`
  - iOS: `.shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 4)`

### Motion
- **duration-fast**
  - Web: `150ms`
  - iOS: `.animation(.easeInOut(duration: 0.150))`
- **easing-standard**
  - Web: `cubic-bezier(0.2, 0, 0, 1)`
  - iOS: `Custom EaseOut`

### Typography (Fonts)
- **heading font**
  - Web: `Outfit`
  - iOS: `Font.custom("Outfit", size: XX)`
- **body font**
  - Web: `Inter`
  - iOS: `Font.custom("Inter", size: XX)`

### Logo
- **Logo asset 来源**
  - Web: `public/images/logo.png`
  - iOS: `Assets.xcassets/Logo`

## Conflict & Double Source State
- `MASTER.md` shows `Teal (#0D9488)` whilst `globals.css` overrides with `Azure Blue (#0080FF)`. *Decision:* Sync iOS with `globals.css` (Azure Blue).
- **iOS Implementation Issue**: iOS contains duplicate references. `Color+Theme.swift` vs `Color+Brand.swift`.
- **Recommendation**: Merge logic mapping to a single source of truth: `ZYDesignTokens.swift`.