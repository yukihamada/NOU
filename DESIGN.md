# Design System: NOU

**Product:** NOU — Private AI assistant, entirely on your device.

## 1. Visual Theme & Atmosphere

NOU feels **calm, trustworthy, and effortlessly modern** — like a high-end tool that respects your intelligence. The design avoids visual clutter and technical jargon. Every screen should feel spacious, with generous whitespace and a deliberate sense of quiet confidence.

**Key words:** Minimal, warm, breathable, premium, private.

**Anti-patterns to avoid:**
- Rainbow of agent colors (no more than 3 accent colors in any view)
- Exposed implementation details (model IDs, build numbers, agent names)
- Gradient overuse (reserve gradients for 1-2 hero moments per screen)
- Dense information displays (settings should feel like preferences, not a control panel)

## 2. Color Palette & Roles

### Primary
| Name | Hex | Role |
|------|-----|------|
| Indigo | `#5B5BD6` | Primary actions, brand identity, user message bubbles |
| Indigo Light | `#8B8BD8` | Hover/pressed states, secondary accents |
| Indigo Soft | `#5B5BD6` at 8% | Subtle backgrounds, selected states |

### Neutral
| Name | Hex | Role |
|------|-----|------|
| Surface | system background | Main canvas, cards |
| Surface Elevated | secondary system bg | Input fields, secondary cards |
| Surface Chat | `#F5F5F8` light / `#1C1C1E` dark | Chat background, slightly off-white/off-black |
| Text Primary | system label | Headlines, body text |
| Text Secondary | secondary label | Descriptions, metadata |
| Text Tertiary | tertiary label | Timestamps, hints |

### Semantic
| Name | Hex | Role |
|------|-----|------|
| Emerald | `#10B981` | Success, connected states, privacy badges |
| Amber | `#F59E0B` | Warnings, quality indicators |
| Rose | `#EF4444` | Errors, destructive actions, recording |
| Teal | `#14B8A6` | Mac connection, secondary feature accent |

### Rule: No more than 3 colors visible at once (excluding text grays). Primary indigo dominates. Semantic colors appear only when conveying status.

## 3. Typography Rules

**System font only** — SF Pro (system default). Rounded variant for headlines, default for body.

| Level | Size | Weight | Design | Usage |
|-------|------|--------|--------|-------|
| Display | 34pt | Bold | Rounded | App name on onboarding only |
| Title | 22pt | Bold | Rounded | Section headers, onboarding titles |
| Headline | 17pt | Semibold | Rounded | Card titles, button labels |
| Body | 17pt | Regular | Default | Chat messages, descriptions |
| Subheadline | 15pt | Regular | Default | Secondary descriptions |
| Caption | 13pt | Medium | Rounded | Labels, badges, section headers |
| Micro | 11pt | Regular | Rounded | Timestamps, tertiary info |

**Rules:**
- Never use font sizes below 11pt
- Caption text uses UPPERCASE + letter-spacing only for section headers
- Body text line spacing: 1.4x for readability
- Monospaced font only inside code blocks

## 4. Component Stylings

### Buttons
- **Primary CTA:** Full-width capsule, indigo fill, white text, 18pt vertical padding. Subtle shadow (indigo at 20%, 8px blur, 4px y-offset). Used once per screen maximum.
- **Secondary:** Same shape but surface-elevated fill, primary text color. No shadow.
- **Icon buttons:** 40x40pt circle, surface-elevated fill. 18pt icon. Used in top bar.
- **Destructive:** Rose text, no fill. Appears only in Settings.

### Cards
- Corner radius: 16pt consistently
- Background: Surface (system background)
- Shadow: Black at 4%, 8px blur, 2px y-offset
- Border: Only for selected/active state — primary color at 15% opacity, 1px
- Internal padding: 16pt all sides
- **Suggestion cards (empty state):** 2x2 grid, 110pt height, icon top-left, title+subtitle bottom-left, subtle colored left border (2pt)

### Chat Bubbles
- **User:** Indigo gradient fill (top-leading to bottom-trailing), white text. Rounded rectangle with small top-right corner (4pt) and large other corners (18pt). Subtle indigo shadow.
- **Assistant:** Surface-elevated fill, primary text. Small top-left corner. No shadow. Preceded by a small "N" text avatar (30pt circle, indigo gradient).
- **Max width:** 75% of screen width
- **Spacing between messages:** 16pt

### Input Area
- Text field: Surface-elevated background, 20pt corner radius (pill-like), 16pt horizontal padding, 12pt vertical padding
- When focused: 1.5px indigo border at 40% opacity
- Send button: 42pt circle, indigo gradient when active, surface-elevated when empty
- Mic button: 40pt circle, surface-elevated default, rose background when recording

### Status Badges
- Capsule shape, 6pt vertical padding, 10pt horizontal padding
- Success (connected/on-device): Emerald text + emerald at 10% fill
- Mac connection: Teal text + teal at 10% fill

## 5. Layout Principles

### Spacing Scale
| Token | Value | Usage |
|-------|-------|-------|
| xs | 4pt | Icon-to-text gaps, tight grouping |
| sm | 8pt | Between related elements |
| md | 12pt | Within cards, form field padding |
| lg | 16pt | Between cards, section content padding |
| xl | 24pt | Between sections |
| xxl | 32pt | Major section breaks, top padding |

### Screen Structure
- **Top bar:** 16pt horizontal padding, 12pt vertical. No logo icon — just "NOU" text (22pt bold rounded) with status underneath.
- **Chat area:** 16pt horizontal padding. Messages aligned left (assistant) or right (user).
- **Input area:** 16pt horizontal padding, 12pt vertical. Sits at keyboard edge.
- **Settings:** Standard iOS insetGrouped list. No custom styling except section content.

### Touch Targets
- Minimum 44x44pt for all interactive elements
- Icon buttons: 40pt visible + 4pt hit area padding

## 6. Depth & Elevation

Three levels only:
1. **Base:** Chat background (surface-chat). No shadow.
2. **Raised:** Cards, input field, top bar. Shadow: black 4%, 8px blur, 2px y.
3. **Floating:** Modals, discovery banners. Shadow: black 8%, 16px blur, 4px y.

**No stacked shadows.** If an element is inside a card, only the card gets a shadow.

## 7. Do's and Don'ts

### Do
- Use whitespace generously — when in doubt, add more space
- Keep screens to one primary action
- Use system colors for surfaces (automatic dark mode)
- Show status through color, not text ("green dot" = working, not "Status: Active")
- Animate state changes with spring(duration: 0.3)

### Don't
- Show model IDs, parameter counts, or quantization types to users
- Use more than one gradient per screen
- Display technical metrics (tokens/sec, context length, KV cache type)
- Use rainbow-colored agent chips or badges
- Add borders AND shadows to the same element
- Use the NOULogo component more than once per screen

## 8. Responsive Behavior

- iPhone SE: All content must be usable without horizontal scrolling
- iPhone Pro Max: Content max-width stays comfortable (no stretched layouts)
- Dynamic Type: Respect accessibility text size settings for body and caption text
- Landscape: Not actively supported — lock to portrait

## 9. AI Agent Prompt Guide

When generating NOU UI code:
- Import: `import SwiftUI` + `import UIKit`
- Colors: `NOU.Colors.primary`, `NOU.Colors.surfacePrimary`, etc.
- Fonts: `NOU.Typography.headline()`, `NOU.Typography.body()`, etc.
- Spacing: `NOU.Spacing.lg` (16pt), `NOU.Spacing.xl` (24pt), etc.
- Radius: `NOU.Radius.lg` (16pt) for cards
- Haptics: `Haptics.light()` for taps, `Haptics.medium()` for actions, `Haptics.success()` for completions
- Gradients: `NOU.Gradients.brand` for hero elements only
