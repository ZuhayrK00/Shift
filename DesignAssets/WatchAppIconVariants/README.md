# Future Watch app icon variants

These dark and tinted 1024×1024 source images are intentionally kept outside
the Watch app icon asset catalog for the stable Xcode 26 release. Xcode 26
treats those newer appearance roles as unassigned asset-catalog children and
emits archive warnings.

When the app moves to the final Xcode 27 toolchain, add these images back to
`ShiftWatch/Assets.xcassets/AppIcon.appiconset` using Xcode's dark and tinted
appearance slots.
