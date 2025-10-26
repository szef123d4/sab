-- Ultimate Pet Simulator X Script Collection
-- Combined into one organized script

if game.PlaceId ~= 109983668079237 then
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local Camera = Workspace.CurrentCamera

-- ========== CONFIGURATION ==========
local CONFIG = {
    -- Best Animal ESP
    SCAN_INTERVAL = 1,
    
    -- Ragdoll Movement
    BASE_SPEED = 50,
    VERTICAL_BOOST = 5,
    
    -- Plot ESP
    PLOT_UPDATE_INTERVAL = 0.1,
    MAX_STABLE_TIME = 1,
    
    -- Speed Booster
    BOOST_SPEED = 27,
    STEALING_THRESHOLD = 20.5,
    
    -- Flying
    FLY_SPEED = 70,
    FLY_REMOTE_DELAY = 0.1,
    HOOK_TOOL_NAME = "Grapple Hook",
    FLY_KEY = Enum.KeyCode.F,
    FLY_TO_ANIMAL_KEY = Enum.KeyCode.Z,
    
    -- Desync
    DESYNC_KEY = Enum.KeyCode.G,
    
    -- Anti-Negative Effects
    NORMAL_FOV = 70,
    
    -- Server Hopper
    SERVER_HOP_KEY = Enum.KeyCode.P,
    
    -- Auto Lazer
    AUTO_LAZER_KEY = Enum.KeyCode.L
}

-- ========== GLOBAL VARIABLES ==========
local bestAnimalESP = nil
local bestAnimalValue = 0
local lastBestAnimalId = nil
local currentNotification = nil
local lastScanTime = 0

-- Ragdoll Movement
local keys = {}

-- Plot ESP
local activeESPs = {}
local lastTimes = {}
local stableCounters = {}
local lastUpdate = 0

-- Flying
local LocalFlying = false
local FlyingToAnimal = false
local ctrl = false
local spaceKey = false
local flyToggle = false

-- Player ESP
local espObjects = {}

-- Anti-Negative Effects
local UseItemEvent

-- Auto Lazer
local autoLazerEnabled = false
local autoLazerThread = nil
local blacklistNames = {"szymonyut"}
local blacklist = {}
for _, name in ipairs(blacklistNames) do
    blacklist[string.lower(name)] = true
end

-- ========== UTILITY FUNCTIONS ==========

-- Show transparent notification
local function showNotification(title, text, isError)
    if currentNotification then
        currentNotification:Destroy()
    end
    
    local playerGui = player:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "Notification"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 280, 0, 70)
    frame.Position = UDim2.new(0.5, -140, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BackgroundTransparency = 0.9
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = isError and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 255, 100)
    stroke.Parent = frame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 20)
    titleLabel.Position = UDim2.new(0, 0, 0, 5)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = isError and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 255, 100)
    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Parent = frame

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, 0, 0, 45)
    infoLabel.Position = UDim2.new(0, 0, 0, 20)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = text
    infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoLabel.TextSize = 12
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.Parent = frame

    -- Fade in animation
    frame.BackgroundTransparency = 1
    titleLabel.TextTransparency = 1
    infoLabel.TextTransparency = 1
    stroke.Transparency = 1
    
    TweenService:Create(frame, TweenInfo.new(0.5), {BackgroundTransparency = 0.9}):Play()
    TweenService:Create(titleLabel, TweenInfo.new(0.5), {TextTransparency = 0}):Play()
    TweenService:Create(infoLabel, TweenInfo.new(0.5), {TextTransparency = 0}):Play()
    TweenService:Create(stroke, TweenInfo.new(0.5), {Transparency = 0}):Play()

    currentNotification = screenGui

    -- Auto remove after 4 seconds
    task.spawn(function()
        task.wait(4)
        if currentNotification == screenGui then
            TweenService:Create(frame, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
            TweenService:Create(titleLabel, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
            TweenService:Create(infoLabel, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
            TweenService:Create(stroke, TweenInfo.new(0.5), {Transparency = 1}):Play()
            task.wait(0.5)
            screenGui:Destroy()
            if currentNotification == screenGui then
                currentNotification = nil
            end
        end
    end)
end

-- Extract number from generation string
local function extractNumber(str)
    if not str then return 0 end
    local numberStr = str:match("([%d%.]+[kKmMbB]?)") or "0"
    numberStr = numberStr:gsub("%s", ""):lower()
    local multiplier = 1
    if numberStr:find("b") then multiplier = 1e9; numberStr = numberStr:gsub("b","")
    elseif numberStr:find("m") then multiplier = 1e6; numberStr = numberStr:gsub("m","")
    elseif numberStr:find("k") then multiplier = 1e3; numberStr = numberStr:gsub("k","") end
    return (tonumber(numberStr) or 0) * multiplier
end



-- ========== AUTO LAZER CAP ==========

local autoLazerEnabled = false
local autoLazerThread = nil
local blacklistNames = {"szymonyut"}
local blacklist = {}
for _, name in ipairs(blacklistNames) do
    blacklist[string.lower(name)] = true
end

local function getLazerRemote()
    local remote = nil
    pcall(function()
        if ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("Net") then
            remote = ReplicatedStorage.Packages.Net:FindFirstChild("RE/UseItem") or ReplicatedStorage.Packages.Net:FindFirstChild("RE"):FindFirstChild("UseItem")
        end
        if not remote then
            remote = ReplicatedStorage:FindFirstChild("RE/UseItem") or ReplicatedStorage:FindFirstChild("UseItem")
        end
    end)
    return remote
end

local function isValidTarget(player)
    if not player or not player.Character or player == Players.LocalPlayer then return false end
    local name = player.Name and string.lower(player.Name) or ""
    if blacklist[name] then return false end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return false end
    if humanoid.Health <= 0 then return false end
    return true
end

local function findNearestAllowed()
    if not Players.LocalPlayer.Character or not Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = Players.LocalPlayer.Character.HumanoidRootPart.Position
    local nearest = nil
    local nearestDist = math.huge
    for _, pl in ipairs(Players:GetPlayers()) do
        if isValidTarget(pl) then
            local targetHRP = pl.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP then
                local d = (Vector3.new(targetHRP.Position.X, 0, targetHRP.Position.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = pl
                end
            end
        end
    end
    return nearest
end

local function safeFire(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return end
    local targetHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end
    local remote = getLazerRemote()
    local args = {
        [1] = targetHRP.Position,
        [2] = targetHRP
    }
    if remote and remote.FireServer then
        pcall(function()
            remote:FireServer(unpack(args))
        end)
    end
end

local function autoEquipLaserCape()
    local backpack = player:WaitForChild("Backpack")
    local character = player.Character
    
    -- Look specifically for "Laser Cape" in backpack
    local laserCape = backpack:FindFirstChild("Laser Cape")
    
    -- Equip the Laser Cape if found
    if laserCape and character then
        laserCape.Parent = character
        task.wait(0.1) -- Small delay to ensure tool is equipped
    end
    
    return laserCape ~= nil
end

local function autoLazerWorker()
    while autoLazerEnabled do
        -- Auto equip Laser Cape before firing
        autoEquipLaserCape()
        
        local target = findNearestAllowed()
        if target then
            safeFire(target)
        end
        local t0 = tick()
        while tick() - t0 < 0.6 do
            if not autoLazerEnabled then break end
            RunService.Heartbeat:Wait()
        end
    end
end

local function toggleAutoLazer()
    autoLazerEnabled = not autoLazerEnabled
    
    if autoLazerEnabled then
        -- Try to equip Laser Cape when enabling
        autoEquipLaserCape()
        autoLazerThread = task.spawn(autoLazerWorker)
    else
        if autoLazerThread then
            task.cancel(autoLazerThread)
            autoLazerThread = nil
        end
    end
end

-- ========== SERVER HOPPER ==========

local function loadServerHopper()
    local success, result = pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/szef123d4/sab/refs/heads/main/serverhoopper"))()
    end)
    
    if success then
        showNotification("Server Hopper", "✅ Server hopper loaded successfully!\nPress P to hop servers.")
        return true
    else
        showNotification("Server Hopper", "❌ Failed to load server hopper:\n" .. tostring(result), true)
        return false
    end
end

-- ========== SENTRY RESIZER ==========

local function resizeSentry(part)
    if part:IsA("Part") and part.Name:sub(1,7) == "Sentry_" then
        part.Size = Vector3.new(50, 50, 100)
        part.CanCollide = false
        
        part.Transparency = 0.5
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 0, 0)
    end
end

local function setupSentryResizer()
    for _, obj in ipairs(Workspace:GetChildren()) do
        resizeSentry(obj)
    end

    Workspace.ChildAdded:Connect(function(child)
        resizeSentry(child)
    end)
    
    for _, obj in ipairs(Workspace:GetDescendants()) do
        resizeSentry(obj)
    end
    
    Workspace.DescendantAdded:Connect(function(descendant)
        resizeSentry(descendant)
    end)
    
    showNotification("Sentry Resizer", "✅ Sentry resizer activated!\nAll sentries will be resized.")
end

-- ========== ANTI-NEGATIVE EFFECTS ==========

local function setupAntiNegativeEffects()
    local success, netPackage = pcall(function()
        return ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net")
    end)
    
    if success and netPackage then
        local ok, netModule = pcall(require, netPackage)
        if ok and netModule then
            UseItemEvent = netModule:RemoteEvent("UseItem")
        end
    end
    
    if not UseItemEvent then
        warn("⚠️ Could not load UseItem remote for anti-negative effects")
        return
    end
end

local function getControlsAndOriginal()
    local controls, original
    local success, playerModule = pcall(function()
        return player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
    end)
    if success and playerModule then
        local ok, pm = pcall(function() return require(playerModule) end)
        if ok and pm and pm.GetControls then
            controls = pm:GetControls()
        end
    end

    local ok2, CharacterController = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Controllers"):WaitForChild("CharacterController"))
    end)
    if ok2 and CharacterController then
        original = CharacterController.originalMoveFunction
    end
    return controls, original
end

local function restoreNormalState()
    local controls, original = getControlsAndOriginal()

    if controls and original and controls.moveFunction ~= original then
        pcall(function() controls.moveFunction = original end)
    end

    if Camera.FieldOfView ~= CONFIG.NORMAL_FOV then
        Camera.FieldOfView = CONFIG.NORMAL_FOV
    end

    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("BlurEffect") then
            pcall(function() effect:Destroy() end)
        end
    end

    local disco = Lighting:FindFirstChild("DiscoEffect")
    if disco and disco:IsA("ColorCorrectionEffect") then
        disco:Destroy()
    end

    local cc = Lighting:FindFirstChild("ColorCorrection")
    if cc and cc:IsA("ColorCorrectionEffect") then
        cc:Destroy()
    end

    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    if controllers then
        local itemCtrl = controllers:FindFirstChild("ItemController")
        if itemCtrl then
            local paintCtrl = itemCtrl:FindFirstChild("PaintballGunController")
            if paintCtrl then
                for _, obj in ipairs(paintCtrl:GetChildren()) do
                    if obj:IsA("ImageLabel") and obj.Name:match("^Paint") then
                        obj.Visible = false
                    end
                end
            end
        end
    end
end

local function startAntiNegativeEffects()
    RunService.Heartbeat:Connect(restoreNormalState)
    
    RunService.Heartbeat:Connect(function()
        local cc = Lighting:FindFirstChild("ColorCorrection")
        if cc and cc:IsA("ColorCorrectionEffect") then
            cc:Destroy()
        end
    end)
    
    if UseItemEvent then
        UseItemEvent.OnClientEvent:Connect(function(effect)
            if effect == "Bee Attack" or effect == "Boogie" or effect == "PaintballHitted" then
                restoreNormalState()
            end
        end)
    end
end

-- ========== BEST ANIMAL ESP ==========

local function getAnimalId(animalData)
    return tostring(animalData.Value) .. "_" .. animalData.DisplayName
end

local function findAnimalOverheads()
    local currentTime = tick()
    if currentTime - lastScanTime < CONFIG.SCAN_INTERVAL then return {} end
    lastScanTime = currentTime
    local overheads = {}

    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return {} end

    for _, plot in pairs(plotsFolder:GetDescendants()) do
        if plot.Name == "AnimalOverhead" and plot:IsA("BillboardGui") then
            local stolenLabel = plot:FindFirstChild("Stolen")
            local isStolen = stolenLabel and stolenLabel:IsA("TextLabel") and string.upper(stolenLabel.Text) == "FUSING"
            local displayNameLabel = plot:FindFirstChild("DisplayName")
            local genLabel = plot:FindFirstChild("Generation")
            local rarityLabel = plot:FindFirstChild("Rarity")
            if displayNameLabel and genLabel and rarityLabel and not isStolen then
                table.insert(overheads, plot)
            end
        end
    end
    return overheads
end

local function getAnimalData(overhead)
    if not overhead or not overhead.Parent then return nil end
    local displayNameLabel = overhead:FindFirstChild("DisplayName")
    local genLabel = overhead:FindFirstChild("Generation")
    local rarityLabel = overhead:FindFirstChild("Rarity")
    if displayNameLabel and genLabel and rarityLabel then
        return {
            DisplayName = displayNameLabel.Text,
            Generation = genLabel.Text,
            Rarity = rarityLabel.Text,
            Value = extractNumber(genLabel.Text)
        }
    end
    return nil
end

local function getAnimalModel(overhead)
    local parent = overhead.Parent
    while parent do
        if parent:IsA("Model") then return parent end
        if parent == Workspace then break end
        parent = parent.Parent
    end
    return nil
end

local function getAttachPart(overhead)
    local model = getAnimalModel(overhead)
    if model then
        local cframe, size = model:GetBoundingBox()
        local topPosition = cframe.Position + Vector3.new(0, size.Y/2 + 0.5, 0)
        local anchor = Instance.new("Part")
        anchor.Name = "ESPAnchor"
        anchor.Size = Vector3.new(1,1,1)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.Position = topPosition
        anchor.Parent = Workspace
        return anchor
    end
    return overhead.Adornee or overhead
end

local function createTracer(attachPart)
    local beam = Instance.new("Beam")
    beam.Color = ColorSequence.new(Color3.fromRGB(100,255,100))
    beam.Width0 = 0.05
    beam.Width1 = 0.05
    beam.FaceCamera = true
    beam.Texture = "rbxassetid://446111271"
    beam.TextureSpeed = 2
    beam.TextureLength = 2

    local attachment0 = Instance.new("Attachment")
    attachment0.Parent = attachPart

    local attachment1 = Instance.new("Attachment")
    attachment1.Parent = Workspace.CurrentCamera
    attachment1.Position = Vector3.new(0,0,-1)

    beam.Attachment0 = attachment0
    beam.Attachment1 = attachment1
    beam.Parent = attachPart
    return beam
end

local function cleanupESP()
    if bestAnimalESP then
        if bestAnimalESP.ScreenGui then bestAnimalESP.ScreenGui:Destroy() end
        if bestAnimalESP.Tracer then bestAnimalESP.Tracer:Destroy() end
        if bestAnimalESP.AttachPart and bestAnimalESP.AttachPart.Name == "ESPAnchor" then
            bestAnimalESP.AttachPart:Destroy()
        end
        bestAnimalESP = nil
        lastBestAnimalId = nil
    end
end

local function createBestAnimalESP(overhead, animalData)
    if not overhead or not animalData then return nil end
    local animalId = getAnimalId(animalData)
    if lastBestAnimalId == animalId and bestAnimalESP then return bestAnimalESP end

    cleanupESP()
    local playerGui = player:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BestAnimalESP"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local attachPart = getAttachPart(overhead)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BestAnimalESPBillboard"
    billboard.Size = UDim2.new(0,200,0,60)
    billboard.ExtentsOffset = Vector3.new(0,0,0)
    billboard.AlwaysOnTop = true
    billboard.Enabled = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 1000
    billboard.Adornee = attachPart
    billboard.Parent = screenGui

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1,0,1,0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = string.format("%s\n%s\n%s", animalData.DisplayName, animalData.Generation, animalData.Rarity)
    textLabel.TextColor3 = Color3.fromRGB(0,255,0)
    textLabel.TextSize = 14
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextStrokeTransparency = 0
    textLabel.TextStrokeColor3 = Color3.new(0,0,0)
    textLabel.TextYAlignment = Enum.TextYAlignment.Center
    textLabel.Parent = billboard

    local tracer = createTracer(attachPart)

    bestAnimalESP = {
        ScreenGui = screenGui,
        Tracer = tracer,
        AttachPart = attachPart,
        Billboard = billboard
    }

    lastBestAnimalId = animalId
    showNotification("Best Animal Found", string.format("%s\n%s\n%s", animalData.DisplayName, animalData.Generation, animalData.Rarity))
    return bestAnimalESP
end

local function findBestAnimal()
    local overheads = findAnimalOverheads()
    local bestValue, bestOverhead, bestData = -math.huge, nil, nil

    for _, overhead in pairs(overheads) do
        local data = getAnimalData(overhead)
        if data and data.Value > bestValue then
            bestValue = data.Value
            bestOverhead = overhead
            bestData = data
        end
    end

    if bestOverhead and bestData then
        createBestAnimalESP(bestOverhead, bestData)
        bestAnimalValue = bestValue
    end
end

-- ========== RAGDOLL MOVEMENT ==========

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        keys[input.KeyCode] = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        keys[input.KeyCode] = false
    end
end)

local function getInputVector(cam)
    local vec = Vector3.new(0,0,0)
    if keys[Enum.KeyCode.W] then vec = vec + cam.CFrame.LookVector end
    if keys[Enum.KeyCode.S] then vec = vec - cam.CFrame.LookVector end
    if keys[Enum.KeyCode.A] then vec = vec - cam.CFrame.RightVector end
    if keys[Enum.KeyCode.D] then vec = vec + cam.CFrame.RightVector end
    vec = Vector3.new(vec.X,0,vec.Z)
    if vec.Magnitude > 0 then
        vec = vec.Unit
    end
    return vec
end

local function enableRagdollMovement(char)
    local humanoid = char:WaitForChild("Humanoid")
    local hrp = char:WaitForChild("HumanoidRootPart")

    RunService.Heartbeat:Connect(function()
        if humanoid:GetState() == Enum.HumanoidStateType.Physics then
            local inputVector = getInputVector(workspace.CurrentCamera)
            if inputVector.Magnitude > 0 then
                hrp.Velocity = Vector3.new(
                    inputVector.X * CONFIG.BASE_SPEED,
                    CONFIG.VERTICAL_BOOST,
                    inputVector.Z * CONFIG.BASE_SPEED
                )
            end
        end
    end)
end

-- ========== PLOT ESP ==========

local function parseTime(text)
    if not text or text == "" then return 0 end
    text = text:lower():gsub("%s", "")
    local value, unit = text:match("(%d+)([sm]?)")
    value = tonumber(value) or 0
    unit = unit or "s"
    if value == 0 then return 0 end
    if unit == "m" then return value * 60 else return value end
end

local function getPlotAttachPart(plotModel)
    if plotModel:IsA("BasePart") then return plotModel end
    if plotModel.PrimaryPart then return plotModel.PrimaryPart end
    for _, part in pairs(plotModel:GetDescendants()) do
        if part:IsA("BasePart") then return part end
    end
    return nil
end

local function createOrUpdatePlotESP(plot, secondsRemaining)
    local espData = activeESPs[plot]
    local attachPart = getPlotAttachPart(plot)
    if not attachPart then return end
    
    if not espData then
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "PlotESP_" .. plot.Name
        screenGui.ResetOnSpawn = false
        screenGui.Parent = player:WaitForChild("PlayerGui")
        
        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 120, 0, 40)
        billboard.Adornee = attachPart
        billboard.ExtentsOffset = Vector3.new(0, 5, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = screenGui

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1,0,1,0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1,1,1)
        label.Font = Enum.Font.GothamBold
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3 = Color3.new(0,0,0)
        label.TextScaled = true
        label.Parent = billboard

        espData = {
            ScreenGui = screenGui,
            Billboard = billboard,
            Label = label
        }
        activeESPs[plot] = espData
    end

    espData.Label.Text = string.format("%ds", secondsRemaining)
end

local function removePlotESP(plot)
    local espData = activeESPs[plot]
    if espData then
        if espData.ScreenGui and espData.ScreenGui.Parent then
            espData.ScreenGui:Destroy()
        end
        activeESPs[plot] = nil
    end
end

local function updatePlotESP()
    if tick() - lastUpdate < CONFIG.PLOT_UPDATE_INTERVAL then return end
    lastUpdate = tick()

    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return end

    for _, plot in pairs(plotsFolder:GetChildren()) do
        local multiplierPart = plot:FindFirstChild("Multiplier")
        if multiplierPart then
            local mainGui = multiplierPart:FindFirstChild("Main")
            if mainGui and mainGui:IsA("BillboardGui") then
                local amountLabel = mainGui:FindFirstChild("Amount")
                if amountLabel and amountLabel:IsA("TextLabel") then
                    if amountLabel.Text == "0x" then
                        removePlotESP(plot)
                        lastTimes[plot] = nil
                        stableCounters[plot] = nil
                    else
                        local remainingLabel
                        for _, obj in pairs(plot:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Name == "RemainingTime" then
                                remainingLabel = obj
                                break
                            end
                        end

                        if remainingLabel then
                            local seconds = parseTime(remainingLabel.Text)

                            if seconds > 0 then
                                if lastTimes[plot] == seconds then
                                    stableCounters[plot] = (stableCounters[plot] or 0) + CONFIG.PLOT_UPDATE_INTERVAL
                                else
                                    stableCounters[plot] = 0
                                    lastTimes[plot] = seconds
                                end

                                if stableCounters[plot] <= CONFIG.MAX_STABLE_TIME then
                                    createOrUpdatePlotESP(plot, seconds)
                                else
                                    removePlotESP(plot)
                                end
                            else
                                removePlotESP(plot)
                                lastTimes[plot] = nil
                                stableCounters[plot] = nil
                            end
                        else
                            removePlotESP(plot)
                            lastTimes[plot] = nil
                            stableCounters[plot] = nil
                        end
                    end
                else
                    removePlotESP(plot)
                    lastTimes[plot] = nil
                    stableCounters[plot] = nil
                end
            else
                removePlotESP(plot)
                lastTimes[plot] = nil
                stableCounters[plot] = nil
            end
        else
            removePlotESP(plot)
            lastTimes[plot] = nil
            stableCounters[plot] = nil
        end
    end
end

-- ========== SPEED BOOSTER ==========

local function getMovementInput()
    local Char = player.Character or player.CharacterAdded:Wait()
    local HRP = Char:WaitForChild("HumanoidRootPart")
    local Hum = Char:FindFirstChildOfClass("Humanoid")
    if not Char or not HRP or not Hum then return Vector3.new(0,0,0) end
    local moveVector = Hum.MoveDirection
    if moveVector.Magnitude > 0.1 then
        return Vector3.new(moveVector.X, 0, moveVector.Z).Unit
    end
    return Vector3.new(0,0,0)
end

local function startSpeedControl()
    RunService.Heartbeat:Connect(function()
        local Char = player.Character or player.CharacterAdded:Wait()
        local HRP = Char:WaitForChild("HumanoidRootPart")
        local Hum = Char:FindFirstChildOfClass("Humanoid")
        if not Char or not HRP or not Hum then return end

        local inputDir = getMovementInput()

        if Hum.WalkSpeed <= CONFIG.STEALING_THRESHOLD and inputDir.Magnitude > 0 then
            HRP.AssemblyLinearVelocity = Vector3.new(
                inputDir.X * CONFIG.BOOST_SPEED,
                HRP.AssemblyLinearVelocity.Y,
                inputDir.Z * CONFIG.BOOST_SPEED
            )
        end
    end)
end

-- ========== FLYING SYSTEM ==========

local LvName = "flyLinearVelocity"
local AoName = "flyAlignOrientation"
local controlModule = require(player.PlayerScripts.PlayerModule.ControlModule)

local cooldownEvent = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"):WaitForChild("RE/Tools/Cooldown")
local useItemEvent = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"):WaitForChild("RE/UseItem")

local function fireRemotes()
    cooldownEvent:FireServer("\006\001\bB\006\001\bB")
    useItemEvent:FireServer(0.4773959477742513)
end

local function startFlying()
    if LocalFlying then return end
    LocalFlying = true

    local LV = Instance.new("LinearVelocity", root)
    local AO = Instance.new("AlignOrientation", root)

    LV.MaxForce = math.huge
    AO.MaxTorque = math.huge
    AO.Mode = Enum.OrientationAlignmentMode.OneAttachment

    LV.Attachment0 = root.RootAttachment
    AO.Attachment0 = root.RootAttachment

    LV.Name = LvName
    AO.Name = AoName

    humanoid.PlatformStand = true
end

local function stopFlying()
    if not LocalFlying then return end
    LocalFlying = false
    FlyingToAnimal = false

    local LV = root:FindFirstChild(LvName)
    local AO = root:FindFirstChild(AoName)

    humanoid.PlatformStand = false

    if LV then LV:Destroy() end
    if AO then AO:Destroy() end
    
    local tool = character:FindFirstChild(CONFIG.HOOK_TOOL_NAME)
    if tool then tool.Parent = player.Backpack end
end

local function toggleHookFly()
    flyToggle = not flyToggle
    if flyToggle then
        local tool = player.Backpack:FindFirstChild(CONFIG.HOOK_TOOL_NAME)
        if tool then tool.Parent = character end
        startFlying()
        task.spawn(function()
            while flyToggle do
                fireRemotes()
                task.wait(CONFIG.FLY_REMOTE_DELAY)
            end
        end)
    else
        stopFlying()
        local tool = character:FindFirstChild(CONFIG.HOOK_TOOL_NAME)
        if tool then tool.Parent = player.Backpack end
    end
end

local function findBestAnimalForFlight()
    local bestValue = 0
    local bestPart = nil
    local bestData = nil
    
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj.Name == "AnimalOverhead" and obj:IsA("BillboardGui") then
            local stolenLabel = obj:FindFirstChild("Stolen")
            local isStolen = stolenLabel and stolenLabel:IsA("TextLabel") and string.upper(stolenLabel.Text) == "FUSING"
            
            if not isStolen then
                local displayNameLabel = obj:FindFirstChild("DisplayName")
                local genLabel = obj:FindFirstChild("Generation")
                local rarityLabel = obj:FindFirstChild("Rarity")
                
                if displayNameLabel and genLabel then
                    local value = extractNumber(genLabel.Text)
                    
                    if value > bestValue then
                        bestValue = value
                        local animalModel = obj.Parent
                        while animalModel and animalModel ~= Workspace do
                            if animalModel:IsA("Model") then
                                local isPriority = false
                                local deliveryHitbox = nil
                                local podiumModel = nil
                                
                                local current = animalModel.Parent
                                while current and current ~= Workspace do
                                    if current:IsA("Model") and current.Name:find("AnimalPodium") then
                                        local podiumNumber = tonumber(current.Name:match("%d+"))
                                        if podiumNumber and podiumNumber >= 1 and podiumNumber <= 10 then
                                            isPriority = true
                                            podiumModel = current
                                            deliveryHitbox = current:FindFirstChild("DeliveryHitbox")
                                            if not deliveryHitbox then
                                                local parentPlot = current.Parent
                                                if parentPlot and parentPlot:IsA("Model") then
                                                    deliveryHitbox = parentPlot:FindFirstChild("DeliveryHitbox")
                                                end
                                            end
                                            break
                                        end
                                    end
                                    current = current.Parent
                                end
                                
                                if isPriority and deliveryHitbox then
                                    bestPart = deliveryHitbox
                                    bestData = {
                                        DisplayName = displayNameLabel.Text,
                                        Generation = genLabel.Text,
                                        Rarity = rarityLabel and rarityLabel.Text or "Unknown",
                                        IsPriority = true,
                                        PodiumName = podiumModel and podiumModel.Name or "Priority Podium"
                                    }
                                else
                                    bestPart = animalModel:FindFirstChild("HumanoidRootPart") or animalModel:FindFirstChild("Head") or animalModel.PrimaryPart or animalModel
                                    bestData = {
                                        DisplayName = displayNameLabel.Text,
                                        Generation = genLabel.Text,
                                        Rarity = rarityLabel and rarityLabel.Text or "Unknown",
                                        IsPriority = false
                                    }
                                end
                                break
                            end
                            animalModel = animalModel.Parent
                        end
                    end
                end
            end
        end
    end
    
    return bestPart, bestData
end

local function flyToBestAnimal()
    local targetPart, animalData = findBestAnimalForFlight()
    if not targetPart or not animalData then
        showNotification("No Animal Found", "No animals found in server", true)
        return
    end
    
    local notificationText = animalData.DisplayName .. "\n" .. animalData.Generation
    if animalData.IsPriority then
        notificationText = notificationText .. "\n" .. animalData.PodiumName .. " (Delivery Box)"
    else
        notificationText = notificationText .. "\n" .. "Direct to Animal"
    end
    
    showNotification("Flying to Animal", notificationText)
    
    local tool = player.Backpack:FindFirstChild(CONFIG.HOOK_TOOL_NAME)
    if tool then tool.Parent = character end
    
    startFlying()
    FlyingToAnimal = true
    
    task.spawn(function()
        while FlyingToAnimal and LocalFlying and targetPart and targetPart.Parent do
            local LV = root:FindFirstChild(LvName)
            local AO = root:FindFirstChild(AoName)
            
            if not LV or not AO then break end
            
            local targetPos = targetPart.Position + Vector3.new(0, 10, 0)
            local direction = (targetPos - root.Position).Unit
            local distance = (targetPos - root.Position).Magnitude
            
            if distance < 50 then
                local arrivalText = "Reached " .. animalData.DisplayName
                if animalData.IsPriority then
                    arrivalText = arrivalText .. " Delivery Box"
                end
                showNotification("Arrived", arrivalText)
                stopFlying()
                break
            end
            
            local flySpeed = math.min(CONFIG.FLY_SPEED, distance * 2)
            LV.VectorVelocity = direction * flySpeed
            AO.CFrame = CFrame.lookAt(root.Position, targetPos)
            
            task.wait()
        end
        
        FlyingToAnimal = false
    end)
end

-- ========== ANTI-DEATH & ANTI-KICK ==========


local function applyAntiDeath(state)
    if humanoid then
        for _, s in pairs({
            Enum.HumanoidStateType.FallingDown,
            Enum.HumanoidStateType.Ragdoll,
            Enum.HumanoidStateType.PlatformStanding,
            Enum.HumanoidStateType.Seated
        }) do
            humanoid:SetStateEnabled(s, not state)
        end
        if state then
            humanoid.Health = humanoid.MaxHealth
            humanoid:GetPropertyChangedSignal("Health"):Connect(function()
                if humanoid.Health <= 0 then
                    humanoid.Health = humanoid.MaxHealth
                end
            end)
        end
    end
end

-- Safe respawn function
local function safeCharacterReset()
    if character and character:FindFirstChild("Humanoid") then
        local humanoid = character:FindFirstChild("Humanoid")
        
        showNotification("Auto Respawn", "Respawning character for bug prevention...", false)
        
        -- Use Roblox's proper respawn method
        humanoid.Health = 0
        
        -- Wait for respawn to complete
        task.wait(3)
        showNotification("Auto Respawn", "Character respawned successfully!", false)
    else
        -- If no character, use respawn function
        player:LoadCharacter()
        task.wait(3)
        showNotification("Auto Respawn", "Character loaded successfully!", false)
    end
end

-- Auto respawn when script executes
safeCharacterReset()
-- ========== PLAYER ESP ==========

local function getPlayerColor(player)
    local hue = (player.UserId % 360) / 360
    return Color3.fromHSV(hue, 1, 1)
end

local function getCharacterBoundingBox(character)
    local minVec, maxVec
    for _, part in pairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Anchored == false then
            local pos = part.Position
            if not minVec then
                minVec = pos
                maxVec = pos
            else
                minVec = Vector3.new(
                    math.min(minVec.X, pos.X),
                    math.min(minVec.Y, pos.Y),
                    math.min(minVec.Z, pos.Z)
                )
                maxVec = Vector3.new(
                    math.max(maxVec.X, pos.X),
                    math.max(maxVec.Y, pos.Y),
                    math.max(maxVec.Z, pos.Z)
                )
            end
        end
    end
    if minVec and maxVec then
        local size = maxVec - minVec
        local center = (minVec + maxVec)/2
        return center, size
    else
        return nil, nil
    end
end

local function createPlayerBoundingBox(player)
    if player == Players.LocalPlayer then return end

    local char = player.Character
    if not char then return end

    if espObjects[player] then
        espObjects[player]:Destroy()
        espObjects[player] = nil
    end

    local color = getPlayerColor(player)

    local box = Instance.new("Part")
    box.Name = "BoundingBox"
    box.Anchored = true
    box.CanCollide = false
    box.Transparency = 0.4
    box.Material = Enum.Material.Plastic
    box.Color = color
    box.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0,120,0,30)
    billboard.Adornee = box
    billboard.AlwaysOnTop = true
    billboard.Parent = box

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.fromScale(1,1)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = player.DisplayName
    nameLabel.TextColor3 = color
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    espObjects[player] = box

    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not char or not char.PrimaryPart then
            box:Destroy()
            conn:Disconnect()
            espObjects[player] = nil
            return
        end

        local center, size = getCharacterBoundingBox(char)
        if center and size then
            box.Size = size + Vector3.new(0.5,0.5,0.5)
            box.CFrame = CFrame.new(center)
            billboard.StudsOffset = Vector3.new(0, box.Size.Y/2 + 0.5, 0)
        end
    end)
end

-- ========== MOBILE DESYNC ==========

local function enableMobileDesync()
    local success, error = pcall(function()
        local backpack = player:WaitForChild("Backpack")
        local char = player.Character or player.CharacterAdded:Wait()
        local humanoid = char:WaitForChild("Humanoid")
        
        local packages = ReplicatedStorage:WaitForChild("Packages", 5)
        if not packages then 
            showNotification("❌ Packages not found", "", true)
            return false 
        end
        
        local netFolder = packages:WaitForChild("Net", 5)
        if not netFolder then 
            showNotification("❌ Net folder not found", "", true)
            return false 
        end
        
        local useItemRemote = netFolder:WaitForChild("RE/UseItem", 5)
        local teleportRemote = netFolder:WaitForChild("RE/QuantumCloner/OnTeleport", 5)
        if not useItemRemote or not teleportRemote then 
            showNotification("❌ Remotes not found", "", true)
            return false 
        end

        local toolNames = {"Quantum Cloner", "Brainrot", "brainrot"}
        local tool
        for _, toolName in ipairs(toolNames) do
            tool = backpack:FindFirstChild(toolName) or char:FindFirstChild(toolName)
            if tool then break end
        end
        if not tool then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") then tool=item break end
            end
        end

        if tool and tool.Parent==backpack then
            humanoid:EquipTool(tool)
            task.wait(0.5)
        end

        if setfflag then setfflag("WorldStepMax", "-9999999999") end
        task.wait(0.2)
        useItemRemote:FireServer()
        task.wait(1)
        teleportRemote:FireServer()
        task.wait(2)
        if setfflag then setfflag("WorldStepMax", "-1") end

        showNotification("✅ Desync activated!", "")
        return true
    end)
    if not success then
        showNotification("❌ Error: " .. tostring(error), "", true)
        return false
    end
    return success
end

-- ========== TRANSPARENT DECORATIONS ==========

local function makeDecorationsTransparent(model)
    local decorations = model:FindFirstChild("Decorations")
    if decorations then
        for _, part in ipairs(decorations:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Transparency = 0.4
                if part:FindFirstChildOfClass("SurfaceAppearance") then
                    part:FindFirstChildOfClass("SurfaceAppearance"):Destroy()
                end
                if part:FindFirstChildOfClass("Decal") then
                    part:FindFirstChildOfClass("Decal"):Destroy()
                end
                if part:FindFirstChildOfClass("Texture") then
                    part:FindFirstChildOfClass("Texture"):Destroy()
                end
            end
        end
    end
end

local function setupTransparentDecorations()
    local plotsFolder = Workspace:WaitForChild("Plots")
    for _, model in ipairs(plotsFolder:GetChildren()) do
        makeDecorationsTransparent(model)
    end

    plotsFolder.ChildAdded:Connect(function(model)
        task.wait(0.5)
        makeDecorationsTransparent(model)
    end)

    while true do
        task.wait(2)
        for _, model in ipairs(plotsFolder:GetChildren()) do
            makeDecorationsTransparent(model)
        end
    end
end


-- ========== DISCORD WEBHOOK NOTIFIER ==========

local WEBHOOK_URL = "https://discord.com/api/webhooks/1431391715175956491/ho4G8cdYMUUGzfeeocrtwbOkZ4NmKZmpTj1HuqIjCQ-Av2-K-7zZ222YzOIQt6GM-E_A"

-- Function to send Discord webhook
local function sendRealAnimalWebhook()
    local placeId = game.PlaceId
    local jobId = game.JobId
    local playersCount = #game.Players:GetPlayers()
    
    -- Create a version without cooldown for webhook
    local function findAnimalsForWebhook()
        local overheads = {}
        local plotsFolder = Workspace:FindFirstChild("Plots")
        if not plotsFolder then return {} end

        for _, plot in pairs(plotsFolder:GetDescendants()) do
            if plot.Name == "AnimalOverhead" and plot:IsA("BillboardGui") then
                local stolenLabel = plot:FindFirstChild("Stolen")
                local isStolen = stolenLabel and stolenLabel:IsA("TextLabel") and string.upper(stolenLabel.Text) == "FUSING"
                local displayNameLabel = plot:FindFirstChild("DisplayName")
                local genLabel = plot:FindFirstChild("Generation")
                local rarityLabel = plot:FindFirstChild("Rarity")
                if displayNameLabel and genLabel and rarityLabel and not isStolen then
                    table.insert(overheads, plot)
                end
            end
        end
        return overheads
    end
    
    -- Use the webhook-specific function (no cooldown)
    local overheads = findAnimalsForWebhook()
    if #overheads == 0 then return end
    
    -- Find the highest value animal
    local bestAnimal = nil
    local bestValue = 0
    
    for _, overhead in pairs(overheads) do
        local animalData = getAnimalData(overhead)
        if animalData and animalData.Value > bestValue then
            bestValue = animalData.Value
            bestAnimal = animalData
        end
    end
    
    if not bestAnimal then return end
    
    -- Format animal value as money per second
    local moneyPerSecFormatted
    if bestAnimal.Value >= 1000000000 then
        moneyPerSecFormatted = string.format("💰 %.1fB/s", bestAnimal.Value / 1000000000)
    elseif bestAnimal.Value >= 1000000 then
        moneyPerSecFormatted = string.format("💰 %.1fM/s", bestAnimal.Value / 1000000)
    elseif bestAnimal.Value >= 1000 then
        moneyPerSecFormatted = string.format("💰 %.1fK/s", bestAnimal.Value / 1000)
    else
        moneyPerSecFormatted = string.format("💰 %d/s", bestAnimal.Value)
    end

    -- Create embed
    local embed = {
        title = "🐾 **Brainrot Notify | KLPN Hub**",
        color = 65280,
        fields = {
            {
                name = "**Name**",
                value = bestAnimal.DisplayName,
                inline = false
            },
            {
                name = "**Money per sec**",
                value = moneyPerSecFormatted,
                inline = true
            },
            {
                name = "**Players**",
                value = string.format("👤 %d/%d", playersCount, game.Players.MaxPlayers),
                inline = true
            },
            {
                name = "**Job ID (Mobile)**",
                value = "```" .. jobId .. "```",
                inline = false
            },
            {
                name = "**Job ID (PC)**",
                value = "```" .. jobId .. "```",
                inline = false
            },
            {
                name = "**Join Link**",
                value = "[Click to Join](https://www.roblox.com/games/" .. placeId .. "?jobId=" .. jobId .. ")",
                inline = false
            },
            {
                name = "**Join Script (PC)**",
                value = "```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(" .. placeId .. ",\"" .. jobId .. "\",game.Players.LocalPlayer)\n```",
                inline = false
            }
        },
        timestamp = DateTime.now():ToIsoDate(),
        footer = {
            text = "Made by KLPN Hub • " .. os.date("%m/%d/%Y %I:%M %p")
        }
    }
    
    -- Prepare payload
    local payload = {
        embeds = {embed},
        username = "KLPN Hub Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1128833213672656988/1215321493282160730/standard_1.gif"
    }
    
    -- Send webhook
    local success = pcall(function()
        local HttpService = game:GetService("HttpService")
        local jsonPayload = HttpService:JSONEncode(payload)
        
        if syn and syn.request then
            syn.request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        elseif request then
            request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        end
    end)
end

-- Send webhook once with a small delay to ensure animals are loaded
task.wait(2)
sendRealAnimalWebhook()
-- ========== INPUT HANDLERS ==========

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    -- Flying
    if input.KeyCode == CONFIG.FLY_KEY then
        toggleHookFly()
    elseif input.KeyCode == CONFIG.FLY_TO_ANIMAL_KEY then
        if not FlyingToAnimal then
            flyToBestAnimal()
        end
    -- Desync
    elseif input.KeyCode == CONFIG.DESYNC_KEY then
        task.delay(1, function()
            enableMobileDesync()
        end)
    -- Server Hopper
    elseif input.KeyCode == CONFIG.SERVER_HOP_KEY then
        loadServerHopper()
    -- Auto Lazer
    elseif input.KeyCode == CONFIG.AUTO_LAZER_KEY then
        toggleAutoLazer()
    -- Anti-Death Jump
    elseif input.KeyCode == Enum.KeyCode.Space and character then
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.PlatformStand = true
            task.wait(0.1)
            humanoid.PlatformStand = false
            humanoid.Sit = true
            task.wait(0.1)
            humanoid.Sit = false
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    -- Flying controls
    elseif input.KeyCode == Enum.KeyCode.Space and LocalFlying then
        spaceKey = true
    elseif input.KeyCode == Enum.KeyCode.LeftControl and LocalFlying then
        ctrl = true
    end
end)
-- ========== MAIN LOOPS ==========

-- Best Animal ESP Loop
RunService.Heartbeat:Connect(findBestAnimal)

-- Plot ESP Loop
RunService.Heartbeat:Connect(updatePlotESP)

-- Flying Control Loop
RunService.Heartbeat:Connect(function()
    if LocalFlying then
        local LV = root:FindFirstChild(LvName)
        local AO = root:FindFirstChild(AoName)
        if not LV or not AO then return end

        local moveVector = controlModule:GetMoveVector()
        local direction = workspace.CurrentCamera.CFrame:VectorToWorldSpace(moveVector)

        if moveVector.Magnitude ~= 0 then
            TweenService:Create(LV, TweenInfo.new(0.3), { VectorVelocity = direction * CONFIG.FLY_SPEED }):Play()
        else
            TweenService:Create(LV, TweenInfo.new(0.3), { VectorVelocity = Vector3.new(0, 0, 0) }):Play()
        end

        if spaceKey then
            LV.VectorVelocity = LV.VectorVelocity + Vector3.new(0, CONFIG.FLY_SPEED / 15, 0)
        elseif ctrl then
            LV.VectorVelocity = LV.VectorVelocity - Vector3.new(0, CONFIG.FLY_SPEED / 15, 0)
        end

        if moveVector.Magnitude > 0 then
            AO.RigidityEnabled = true
            AO.Responsiveness = 50
        else
            AO.RigidityEnabled = false
            AO.Responsiveness = 10
        end

        AO.CFrame = workspace.CurrentCamera.CFrame
    end
end)

-- ========== INITIALIZATION ==========

-- Setup anti-negative effects
setupAntiNegativeEffects()

-- Apply anti-death
applyAntiDeath(true)

-- Enable ragdoll movement
enableRagdollMovement(character)

-- Start speed control
startSpeedControl()

-- Start anti-negative effects protection
startAntiNegativeEffects()

-- Setup sentry resizer
task.spawn(setupSentryResizer)

-- Setup player ESP
for _, player in pairs(Players:GetPlayers()) do
    if player ~= Players.LocalPlayer and player.Character then
        createPlayerBoundingBox(player)
    end
end

-- Setup transparent decorations
task.spawn(setupTransparentDecorations)

-- Handle respawns
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
    
    applyAntiDeath(true)
    enableRagdollMovement(character)
    
    if flyToggle then
        task.wait(2)
        toggleHookFly()
    end
end)

-- Handle player joins for ESP
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        createPlayerBoundingBox(player)
    end)
end)

-- Handle player leaves
Players.PlayerRemoving:Connect(function(player)
    if espObjects[player] then
        espObjects[player]:Destroy()
        espObjects[player] = nil
    end
end)

-- Cleanup
player.CharacterRemoving:Connect(function()
    stopFlying()
    cleanupESP()
    if autoLazerThread then
        task.cancel(autoLazerThread)
        autoLazerThread = nil
    end
    autoLazerEnabled = false
end)

-- Final initialization message
showNotification("Script Loaded", "All features activated successfully!\nF: Toggle Fly\nZ: Fly to Best Animal\nG: Mobile Desync\nP: Load Server Hopper\nL: Auto Lazer Cap\nSpace: Anti-Death Jump\nAnti-Negative Effects: Active\nSentry Resizer: Active")





