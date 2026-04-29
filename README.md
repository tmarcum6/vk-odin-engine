# Work in Progress

A minimal game engine built with Vulkan and Odin.

## Tech Stack

- **Language:** [Odin](https://odin-lang.org/)
- **Graphics API:** Vulkan
- **Windowing:** GLFW
- **Platform:** macOS (currently)

## About

A barebones Vulkan game engine demonstrating window creation, GPU enumeration, queue family selection, logical device creation, swapchain setup, and a basic render loop. Currently renders a black screen.

Using and documenting on my personal blog: https://crowsheart.com/

## Requirements

- Odin compiler (`odin`)
- Vulkan SDK
- macOS with GPU supporting Vulkan

## How to Build

```bash
odin run .
```

Or build for release:

```bash
odin build . -release
```

## Current Status

- Window creation via GLFW ✓
- Instance creation with required extensions ✓
- Physical device enumeration ✓
- Surface creation ✓
- Queue family selection (graphics + present) ✓
- Logical device creation ✓
- Swapchain creation ✓
- Render pass ✓
- Command buffer allocation ✓
- Render loop ✓

## What's Next

- Add actual rendering (triangle, meshes)
- Handle window resize
- Add depth buffer
- Framebuffers with proper attachments
- Cleanup on exit (destroy Vulkan resources)
- Window resize handling
- Move initialization to an `AppRunner` struct
- Logger
- AppRunner struct
- Windows/Unix support
