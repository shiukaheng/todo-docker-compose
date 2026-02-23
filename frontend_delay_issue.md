# Frontend Delay Issue: Async State Initialization

## Problem

Several operations require fetching data before the graph can render correctly. The simplest approach (fire async, render immediately, patch when ready) causes visual artifacts — the graph lays out from scratch then snaps to saved positions, or briefly shows the wrong topology before filters apply.

This is not unique to position loading. The same pattern appears in:

- **View switch**: need positions from server before simulation starts
- **App startup**: need both state SSE and display SSE before first meaningful render
- **Any future server-gated initialization**: anything where the engine needs server data to render the correct initial frame

## Desired Behavior

The engine should be able to "gate" rendering until required data is available, showing either nothing or a loading indicator, with a timeout fallback to avoid indefinite blank screens.

## Sketch

```
can render = all required data sources ready

required sources:
  - appState (from state SSE)
  - position data (from GET, per view switch)
  - filter/hide (from display SSE — already reactive)

if !canRender:
  - animation loop skips (already does this for null graphData)
  - optional: show loading indicator

on timeout (e.g. 500ms):
  - give up waiting for missing sources
  - render with whatever is available (fresh layout, no filters, etc.)
```

## Why Defer

This is a UX pattern that applies broadly across the app. Solving it properly means designing a general "readiness gate" system rather than ad-hoc checks per data source. Worth doing once, correctly, after the data flow is cleaned up.
