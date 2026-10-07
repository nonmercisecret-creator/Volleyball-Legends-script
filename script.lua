--[[
    Volleyball Legends - Landing Predictor + Horizontal Facing Lines (Multi-Color)
    - Ring locked to Y = -22.769 (actual court floor)
    - Ring never floats, never drifts upward
    - Enemy facing lines: horizontal, floor-level, HRP-based (stable during spike animations)
    - Each enemy gets a unique line color
]]

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    -- Ring
    Color          = Color3.fromRGB(0, 255, 100),
    Transparency   = 0.35,
    Thickness      = 0.4,
    MinRadius      = 2.5,
    MaxRadius      = 12,
    Gravity        = workspace.Gravity,
    SimulationTime = 6.0,
    StepSize       = 1/480,
    MinVelocity    = 3,
    Enabled        = true,

    SizeScale      = 0.8,

    VelocityChangeThreshold  = 20,
    DirectionChangeThreshold = 0.985,

    SmoothSpeed    = 0.18,
    SizeSmooth     = 0.18,

    FloorY         = -22.769,
    GroundOffset   = 0.15,

    -- Facing lines
    ShowFacingLines        = true,
    FacingLineLength       = 50,
    FacingLineThickness    = 0.15,
    FacingLineTransparency = 0.35,
    TeamCheck              = true,

    -- Palette used to color each opponent's facing line differently.
    -- Assigned in the order players are added to the game.
    FacingLinePalette = {
        Color3.fromRGB(255,  60,  60),   -- red
        Color3.fromRGB( 60, 160, 255),   -- blue
        Color3.fromRGB(255, 200,  60),   -- yellow
        Color3.fromRGB(200,  60, 255),   -- purple
        Color3.fromRGB( 60, 255, 160),   -- green
        Color3.fromRGB(255, 140,  60),   -- orange
        Color3.fromRGB(255,  60, 200),   -- pink
        Color3.fromRGB( 60, 255, 255),   -- cyan
        Color3.fromRGB(160, 255,  60),   -- lime
        Color3.fromRGB(255, 255, 255),   -- white
    },
}

--// Ring state
local ring = nil
local lastBallPos = nil
local lastBallTime = nil

local displayPos = nil
local displayRadius = nil
local lockedLanding = nil
local lastVelocity = nil

--// Facing line state: [player] = { part = Part, color = Color3 }
local facingLines = {}
local colorIndex = 0

--// ============================
-- RING
--// ============================
local function findClientBall()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name:match("^CLIENT_BALL_") and obj:IsA("Model") then
            for _, d in obj:GetDescendants() do
                if d:IsA("BasePart") then return d end
            end
        end
    end
    return nil
end

local function createRing()
    if ring then return end
    ring = Instance.new("Part")
    ring.Name = "VBL_LandingRing"
    ring.Shape = Enum.PartType.Cylinder
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.Material = Enum.Material.Neon
    ring.Color = CONFIG.Color
    ring.Transparency = CONFIG.Transparency
    ring.Size = Vector3.new(CONFIG.Thickness, CONFIG.MinRadius * 2, CONFIG.MinRadius * 2)
    ring.CFrame = CFrame.new(0, CONFIG.FloorY, 0) * CFrame.Angles(0, 0, math.rad(90))
    ring.Parent = workspace
end

local function hideRing()
    if ring then ring.Transparency = 1 end
    displayPos = nil
    displayRadius = nil
    lockedLanding = nil
    lastVelocity = nil
end

local function simulateLandingXZ(pos, vel)
    if vel.Magnitude < CONFIG.MinVelocity then return nil end

    local gravity = Vector3.new(0, -CONFIG.Gravity, 0)
    local p = pos
    local v = vel
    local steps = math.floor(CONFIG.SimulationTime / CONFIG.StepSize)

    for i = 1, steps do
        local nv = v + gravity * CONFIG.StepSize
        local np = p + nv * CONFIG.StepSize

        if np.Y <= CONFIG.FloorY then
            local t = (CONFIG.FloorY - p.Y) / (np.Y - p.Y)
            local landX = p.X + (np.X - p.X) * t
            local landZ = p.Z + (np.Z - p.Z) * t
            return Vector3.new(landX, CONFIG.FloorY, landZ)
        end

        p = np
        v = nv
    end
    return nil
end

local function shouldRecalculate(currentVel)
    if not lastVelocity then return true end
    local speedChange = math.abs(currentVel.Magnitude - lastVelocity.Magnitude)
    local dirDot = currentVel.Unit:Dot(lastVelocity.Unit)
    if speedChange > CONFIG.VelocityChangeThreshold then return true end
    if dirDot < CONFIG.DirectionChangeThreshold then return true end
    return false
end

--// ============================
-- FACING LINES
--// ============================
local function isEnemy(player)
    if not CONFIG.TeamCheck then return true end
    if player == LocalPlayer then return false end
    if not LocalPlayer.Team or not player.Team then return true end
    return player.Team ~= LocalPlayer.Team
end

-- Pick the next color from the palette (cycles if we run out)
local function nextColor()
    colorIndex = colorIndex + 1
    local palette = CONFIG.FacingLinePalette
    return palette[((colorIndex - 1) % #palette) + 1]
end

local function createFacingLine(player)
    if facingLines[player] then return end

    local color = nextColor()

    local line = Instance.new("Part")
    line.Name = "VBL_FacingLine_" .. player.Name
    line.Anchored = true
    line.CanCollide = false
    line.CanQuery = false
    line.CanTouch = false
    line.Material = Enum.Material.Neon
    line.Color = color
    line.Transparency = CONFIG.FacingLineTransparency
    line.Size = Vector3.new(CONFIG.FacingLineThickness, CONFIG.FacingLineThickness, CONFIG.FacingLineLength)
    line.CFrame = CFrame.new(0, -1000, 0)
    line.Parent = workspace

    facingLines[player] = {
        part = line,
        color = color,
    }
end

local function removeFacingLine(player)
    local entry = facingLines[player]
    if entry and entry.part then
        entry.part:Destroy()
    end
    facingLines[player] = nil
end

local function updateFacingLine(player)
    local entry = facingLines[player]
    if not entry or not entry.part then return end
    local line = entry.part

    if not isEnemy(player) then
        line.Transparency = 1
        return
    end

    local char = player.Character
    if not char then
        line.Transparency = 1
        return
    end

    -- Use HumanoidRootPart's facing — it doesn't tilt/swing during animations
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp:IsA("BasePart") then
        line.Transparency = 1
        return
    end

    -- Flatten to horizontal (HRP is already upright, but just in case)
    local raw = hrp.CFrame.LookVector
    local flat = Vector3.new(raw.X, 0, raw.Z)

    if flat.Magnitude < 0.01 then
        line.Transparency = 1
        return
    end
    local dir = flat.Unit

    -- Anchor at the player's feet
    local origin = hrp.Position
    origin = Vector3.new(origin.X, CONFIG.FloorY + CONFIG.GroundOffset + 0.05, origin.Z)

    local mid = origin + dir * (CONFIG.FacingLineLength / 2)

    line.Size = Vector3.new(CONFIG.FacingLineThickness, CONFIG.FacingLineThickness, CONFIG.FacingLineLength)
    line.CFrame = CFrame.new(mid, mid + dir)
    line.Color = entry.color
    line.Transparency = CONFIG.FacingLineTransparency
end

--// ============================
-- PLAYER LIFECYCLE
--// ============================
local function onPlayerAdded(player)
    if player == LocalPlayer then return end
    createFacingLine(player)
end

local function onPlayerRemoving(player)
    removeFacingLine(player)
end

-- Create lines for players already in-game (excluding local)
for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

--// ============================
-- MAIN RENDER LOOP
--// ============================
local renderConn = RunService.RenderStepped:Connect(function()
    -- Ring
    if CONFIG.Enabled then
        local ball = findClientBall()
        if ball then
            local now = tick()
            local vel = ball.AssemblyLinearVelocity
            if vel.Magnitude < 1 and lastBallPos and lastBallTime then
                local dt = now - lastBallTime
                if dt > 0 then vel = (ball.Position - lastBallPos) / dt end
            end
            lastBallPos = ball.Position
            lastBallTime = now

            if shouldRecalculate(vel) then
                lockedLanding = simulateLandingXZ(ball.Position, vel)
                lastVelocity = vel
            end

            if lockedLanding then
                local targetXZ = Vector3.new(lockedLanding.X, 0, lockedLanding.Z)
                if not displayPos then
                    displayPos = targetXZ
                else
                    displayPos = displayPos:Lerp(targetXZ, CONFIG.SmoothSpeed)
                end

                local targetRadius = CONFIG.MinRadius * CONFIG.SizeScale
                if not displayRadius then
                    displayRadius = targetRadius
                else
                    displayRadius = displayRadius + (targetRadius - displayRadius) * CONFIG.SizeSmooth
                end

                createRing()
                ring.Size = Vector3.new(CONFIG.Thickness, displayRadius * 2, displayRadius * 2)
                ring.CFrame = CFrame.new(
                    displayPos.X,
                    CONFIG.FloorY + CONFIG.GroundOffset,
                    displayPos.Z
                ) * CFrame.Angles(0, 0, math.rad(90))
                ring.Color = CONFIG.Color
                ring.Transparency = CONFIG.Transparency
            else
                hideRing()
            end
        else
            hideRing()
        end
    end

    -- Facing lines
    if CONFIG.ShowFacingLines then
        for player, _ in pairs(facingLines) do
            pcall(updateFacingLine, player)
        end
    end
end)

--// ============================
-- CLEANUP
--// ============================
local function cleanup()
    CONFIG.Enabled = false
    if renderConn then renderConn:Disconnect() end
    if ring then ring:Destroy(); ring = nil end
    for player, _ in pairs(facingLines) do
        removeFacingLine(player)
    end
    print("[VBL Predictor] Unloaded.")
end

_G.VBL_Predictor_Cleanup = cleanup
getgenv().VBL_Predictor_Cleanup = cleanup

print("[VBL Predictor] Loaded (ring + multi-color facing lines).")
print("FloorY:", CONFIG.FloorY, "| FacingLineLength:", CONFIG.FacingLineLength)
print("Call VBL_Predictor_Cleanup() to unload.")
