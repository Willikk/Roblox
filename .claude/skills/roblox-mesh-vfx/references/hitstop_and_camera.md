# Hitstop, Camera Shake & Post-Processing Impact Guide

In *Deepwoken* and high-impact action RPGs, the "weight" of a hit comes 50% from visual effects and 50% from camera feedback and frame pausing (*hitstop*).

## 1. What is Hitstop?
Hitstop is a fighting-game technique where both the attacker and defender animations temporarily freeze for a fraction of a second (typically 0.04 to 0.12 seconds) upon landing a hit.
- Light hit (M1 sword swing): `0.04s - 0.06s`
- Heavy hit (Crits, parry counter): `0.08s - 0.14s`

### Implementation Pattern:
```lua
local function applyHitstop(attackerTrack: AnimationTrack?, victimTrack: AnimationTrack?, duration: number)
    if attackerTrack then attackerTrack:AdjustSpeed(0) end
    if victimTrack then victimTrack:AdjustSpeed(0) end
    
    task.delay(duration, function()
        if attackerTrack and attackerTrack.IsPlaying then attackerTrack:AdjustSpeed(1) end
        if victimTrack and victimTrack.IsPlaying then victimTrack:AdjustSpeed(1) end
    end)
end
```

## 2. Directional Camera Shake
Instead of random noise, directional shakes give dramatic impact:
- Push the camera slightly in the direction of the blade cut or knockback.
- Return to normal position within 0.15s using a damped spring or smooth sine lerp.

## 3. Post-Processing Micro-Flash
Triggered locally on the victim's client or observers when a critical strike or parry occurs:
- **Bloom**: Temporarily raise `BloomEffect.Intensity` from `1` to `4` for `0.05s`, then tween back to `1`.
- **ColorCorrection**: Briefly bump `Contrast` to `0.2` and drop `Brightness` slightly to create a sudden high-contrast punch frame.
