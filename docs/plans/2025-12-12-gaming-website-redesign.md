# Bezgelor Gaming Website Redesign

## Overview

Transform the Bezgelor admin portal into a full gaming company website embracing WildStar's bold sci-fi western aesthetic with vibrant neon colors, comic-book energy, and bombastic animations.

## Design Direction

**Visual Identity**: WildStar's original style
- Vibrant neon colors (cyan, magenta, orange, electric blue)
- Comic-book energy with bold typography
- "Devilish charm" personality
- Sci-fi western motifs

**Animation Intensity**: Bombastic
- Parallax scrolling effects
- Dramatic hover transitions
- Glowing/pulsing elements
- Particle effects where appropriate

## Site Structure

### Public Pages (New)

```
/                    - Landing page (hero + all sections)
/features            - Features overview
/features/races      - Playable races detail
/features/classes    - Class system detail
/features/combat     - Combat & telegraph system
/features/housing    - Housing system detail
/features/paths      - Explorer/Soldier/Scientist/Settler
/features/dungeons   - Dungeons & raids
/news                - News/announcements
/download            - Download & setup guide
/community           - Community links & Discord
/about               - About the project
/terms               - Terms of Service
/privacy             - Privacy Policy
```

### Existing Pages (Keep)

```
/login               - Login page (restyle)
/register            - Register page (restyle)
/dashboard           - User dashboard (authenticated)
/characters          - Character management
/settings            - Account settings
/admin/*             - Admin panel
```

## Implementation Batches

### Batch 1: Design System & Color Theme
**Files**: `app.css`, new `gaming.css`

- [ ] Create WildStar-inspired color palette
  - Primary: Electric cyan (#00F0FF)
  - Secondary: Hot magenta (#FF00AA)
  - Accent: Solar orange (#FF6B00)
  - Background: Deep space purple/black gradients
- [ ] Custom DaisyUI theme for gaming aesthetic
- [ ] Typography: Bold display fonts, sci-fi styling
- [ ] Glowing text effects utility classes
- [ ] Animated gradient backgrounds
- [ ] Button hover effects (glow, scale, shimmer)

### Batch 2: Layout Components
**Files**: `layouts.ex`, new layout templates

- [ ] Create `gaming` layout for public pages
  - Transparent navbar over hero
  - Full-width sections
  - Animated footer
- [ ] Gaming navbar component
  - Logo with glow effect
  - Animated menu items
  - CTA buttons (Register/Login)
- [ ] Gaming footer component
  - 4-column grid layout
  - About, Legal, Community, Support sections
  - Social links with hover effects
  - Animated background

### Batch 3: Homepage Hero Section
**Files**: `home.html.heex`, `page_controller.ex`

- [ ] Full-viewport hero section
  - Animated starfield/particle background
  - Large bold headline with glow
  - Tagline with typing effect or reveal
  - CTA buttons: "Play Now" (register) + "Learn More"
  - Parallax layered elements
- [ ] Server status indicator (optional live component)

### Batch 4: Features Section (Homepage)
**Files**: `home.html.heex`, new components

- [ ] Features grid with 6 cards
  - Races, Classes, Combat, Housing, Paths, Dungeons
  - Screenshot placeholder (gradient with icon)
  - Hover: lift, glow, reveal description
  - Link to detail page
- [ ] Section header with animated underline
- [ ] Staggered reveal animation on scroll

### Batch 5: Additional Homepage Sections
**Files**: `home.html.heex`

- [ ] News/Updates section
  - 3 latest news cards
  - Date badges, thumbnails
  - "View All" link
- [ ] Community section
  - Discord widget/link
  - GitHub link
  - Player count (placeholder)
- [ ] Download/Getting Started section
  - System requirements
  - Download button
  - Quick setup steps
- [ ] Final CTA section
  - "Ready to explore Nexus?"
  - Large register button

### Batch 6: Feature Detail Pages
**Files**: New LiveView modules or controllers

- [ ] Create feature page template
  - Hero image area
  - Content sections
  - Related features sidebar
- [ ] `/features/races` - Exile & Dominion races
- [ ] `/features/classes` - All 6 classes
- [ ] `/features/combat` - Telegraph system
- [ ] `/features/housing` - Player housing
- [ ] `/features/paths` - 4 path types
- [ ] `/features/dungeons` - PvE content

### Batch 7: Static Pages & Footer Content
**Files**: New page templates

- [ ] `/about` - About Bezgelor
  - Project history
  - Open source info
  - Credits/contributors
- [ ] `/terms` - Terms of Service (placeholder)
- [ ] `/privacy` - Privacy Policy (placeholder)
- [ ] `/download` - Full download guide
- [ ] `/community` - Community hub page

### Batch 8: Auth Page Restyling
**Files**: `login_live.ex`, `register_live.ex`, `auth` layout

- [ ] Restyle login page with gaming theme
  - Animated background
  - Glowing form fields
  - Themed buttons
- [ ] Restyle register page
- [ ] Update auth layout component

### Batch 9: Animations & Polish
**Files**: `app.css`, `app.js`

- [ ] Scroll-triggered animations (intersection observer)
- [ ] Parallax scroll effects
- [ ] Page transition effects
- [ ] Loading states with themed spinners
- [ ] Micro-interactions (button ripples, etc.)

### Batch 10: Router & Navigation Updates
**Files**: `router.ex`

- [ ] Add routes for all new pages
- [ ] Update navbar links
- [ ] Add breadcrumb support for feature pages
- [ ] Mobile navigation (hamburger menu)

## Color Palette

```css
/* WildStar-Inspired Gaming Theme */
--gaming-cyan: #00F0FF;
--gaming-magenta: #FF00AA;
--gaming-orange: #FF6B00;
--gaming-purple: #9D00FF;
--gaming-green: #00FF88;

--gaming-bg-dark: #0A0A1A;
--gaming-bg-card: #12122A;
--gaming-bg-gradient: linear-gradient(135deg, #0A0A1A 0%, #1A0A2A 50%, #0A1A2A 100%);

--gaming-glow-cyan: 0 0 20px rgba(0, 240, 255, 0.5);
--gaming-glow-magenta: 0 0 20px rgba(255, 0, 170, 0.5);
```

## Typography

- **Headlines**: Bold, wide tracking, uppercase options
- **Body**: Clean sans-serif for readability
- **Accents**: Glowing effects, gradient text

## Screenshot Placeholders

For each feature, create placeholder boxes with:
- Gradient background matching feature theme
- Large icon representing the feature
- "Screenshot Coming Soon" text
- Aspect ratio: 16:9

## Footer Structure

```
+------------------+------------------+------------------+------------------+
|     ABOUT        |      LEGAL       |    COMMUNITY     |     SUPPORT      |
+------------------+------------------+------------------+------------------+
| About Bezgelor   | Terms of Service | Discord          | FAQ              |
| The Team         | Privacy Policy   | GitHub           | Setup Guide      |
| Open Source      | DMCA             | Forums           | Contact          |
| Credits          | Cookie Policy    | Reddit           | Bug Reports      |
+------------------+------------------+------------------+------------------+
|                        [Logo]  [Social Icons]  [Theme Toggle]             |
|                     © 2024 Bezgelor. Not affiliated with NCSOFT.          |
+--------------------------------------------------------------------------+
```

## Dependencies

No new dependencies required - using:
- Tailwind CSS (existing)
- DaisyUI (existing)
- Custom CSS for advanced effects
- Vanilla JS for scroll animations

## Success Criteria

- [ ] Homepage loads with full gaming aesthetic
- [ ] All sections present and styled
- [ ] Animations are smooth (60fps)
- [ ] Mobile responsive
- [ ] Dark/light theme still functional
- [ ] Register/Login prominently accessible
- [ ] Footer complete with all placeholder content
- [ ] Feature pages accessible and styled

## Estimated Scope

- 10 batches of implementation
- ~15-20 new/modified files
- Focus on visual impact and user experience
