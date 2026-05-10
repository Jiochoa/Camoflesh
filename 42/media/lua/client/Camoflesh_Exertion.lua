-- ============================================================
-- Camoflesh - Phase 1: No Corpse Exertion
--
-- When the sandbox option "NoCorpseExertion" is enabled,
-- dragging a zombie corpse does not drain your endurance
-- or cause exertion moodles (Out of Breath / High Exertion).
--
-- How it works: the vanilla drag action calls
-- setMetabolicTarget(Metabolics.MediumWork) every tick, which
-- depletes endurance.  We snapshot the endurance value when
-- dragging begins and restore it each tick, keeping it flat.
--
-- Set CAMOFLESH_DEBUG = true to print diagnostics to console.
-- ============================================================

local CAMOFLESH_DEBUG = false

local function dbg(msg)
    if CAMOFLESH_DEBUG then
        print("[Camoflesh] " .. tostring(msg))
    end
end

-- ── Per-player state ─────────────────────────────────────────────────────────
-- Keyed by playerNum (0-3 for splitscreen).
-- Each entry: { dragging=bool, savedEndurance=number|nil }
local playerState = {}

-- ── Main per-player update ───────────────────────────────────────────────────
local function onPlayerUpdate(player)
    if not SandboxVars or not SandboxVars.Camoflesh then return end

    local num = player:getPlayerNum()
    if not playerState[num] then
        playerState[num] = { dragging = false, savedEndurance = nil }
    end
    local state = playerState[num]

    -- Option disabled: nothing to do, let vanilla run normally
    if not SandboxVars.Camoflesh.NoCorpseExertion then
        state.dragging = false
        state.savedEndurance = nil
        return
    end

    local nowDragging = player:isDraggingCorpse()

    if nowDragging and not state.dragging then
        -- ── Drag just started: snapshot current endurance ───────────────
        state.savedEndurance = player:getStats():get(CharacterStat.ENDURANCE)
        dbg("Drag started. Locking endurance at: " .. tostring(state.savedEndurance))
    elseif nowDragging and state.dragging then
        -- ── Still dragging: restore endurance each tick ──────────────────
        -- The metabolic system will have drained it; put it back.
        if state.savedEndurance then
            player:getStats():set(CharacterStat.ENDURANCE, state.savedEndurance)
        end
    elseif not nowDragging and state.dragging then
        -- ── Drag just ended: release the lock ────────────────────────────
        state.savedEndurance = nil
        dbg("Drag ended. Endurance unlocked.")
    end

    state.dragging = nowDragging
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
