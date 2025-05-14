-- Load Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/Montyrado/Lele/refs/heads/main/RayfieldUI.lua'))()

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Variables
local player = Players.LocalPlayer
local Character = player.Character or player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local ReelFinished = ReplicatedStorage:WaitForChild("events"):WaitForChild("reelfinished")
local CastLine = ReplicatedStorage:WaitForChild("events"):WaitForChild("castline")
local DropBobber = ReplicatedStorage:WaitForChild("events"):WaitForChild("dropbobber")
local ShakeRod = ReplicatedStorage:WaitForChild("events"):WaitForChild("shakerod")

-- Cache required modules
local modules = {
    Library_Fish = require(ReplicatedStorage.shared.modules.library.fish),
    DataController = require(ReplicatedStorage.client.legacyControllers.DataController),
    Cache = require(ReplicatedStorage:WaitForChild("packages").Cache),
    Mutations = nil -- Will be loaded on demand
}

-- State management
local State = {
    isAutoFishing = false,
    currentImplementation = "default",
    fishCaught = 0,
    startTime = 0,
    lastCastTime = 0,
    isReeling = false,
    currentRod = nil,
    testResults = {},
    testStartTime = 0,
    testDuration = 300, -- 5 minutes default test duration
    lastCatchTime = 0,
    totalTime = 0,
    isCasting = false,
    isDroppingBobber = false,
    isShaking = false
}

-- Implementation variants
local Implementations = {
    default = {
        name = "Default Implementation",
        description = "Original instant reel implementation",
        instantReel = function(self)
            if State.isReeling then return end
            State.isReeling = true
            
            local rod = modules.Library_Fish.getCurrentRod()
            if not rod then 
                State.isReeling = false
                return 
            end
            
            -- Default implementation logic
            modules.Library_Fish.reelIn()
            task.wait(0.1)
            State.isReeling = false
        end
    },
    
    noxHub = {
        name = "NoxHub Style",
        description = "Based on NoxHub's implementation",
        instantReel = function(self)
            if State.isReeling then return end
            local reelUI = player.PlayerGui:FindFirstChild("reel")
            if reelUI then
                State.isReeling = true
                local bar = reelUI:FindFirstChild("bar")
                if bar then
                    local reelScript = bar:FindFirstChild("reel")
                    if reelScript and reelScript.Enabled == true then
                        ReelFinished:FireServer(100, true)
                    end
                end
                State.isReeling = false
            end
        end
    },
    
    sasware = {
        name = "Sasware Style",
        description = "Based on Sasware's implementation",
        instantReel = function(self)
            if State.isReeling then return end
            local reelUI = player.PlayerGui:FindFirstChild("reel")
            if reelUI then
                State.isReeling = true
                local bar = reelUI:FindFirstChild("bar")
                if bar then
                    local playerBar = bar:FindFirstChild("playerbar")
                    local targetBar = bar:FindFirstChild("fish")
                    if playerBar and targetBar then
                        local unfilteredTargetPosition = playerBar.Position:Lerp(targetBar.Position, 0.7)
                        local targetPosition = UDim2.fromScale(
                            math.clamp(unfilteredTargetPosition.X.Scale, 0.15, 0.85),
                            unfilteredTargetPosition.Y.Scale
                        )
                        playerBar.Position = targetPosition
                        ReelFinished:FireServer(100, true)
                    end
                end
                State.isReeling = false
            end
        end
    },
    
    enhanced = {
        name = "Enhanced Implementation",
        description = "Optimized implementation with minimal delays",
        instantReel = function(self)
            if State.isReeling then return end
            if State.currentRod and State.currentRod:FindFirstChild("values") then
                local values = State.currentRod.values
                if values:FindFirstChild("bite") and values.bite.Value then
                    State.isReeling = true
                    
                    -- Stop animations
                    for _, track in pairs(Humanoid:GetPlayingAnimationTracks()) do
                        track:Stop(0)
                    end
                    
                    -- Destroy UIs
                    for _, gui in pairs(player.PlayerGui:GetChildren()) do
                        if gui.Name == "fishcaught" or gui.Name == "reel" then
                            gui:Destroy()
                        end
                    end
                    
                    -- Multiple reel attempts
                    for i = 1, 3 do
                        pcall(function()
                            ReelFinished:FireServer(100, true)
                        end)
                    end
                    
                    task.wait(0.15)
                    
                    -- Force reset rod state
                    Humanoid:UnequipTools()
                    task.wait(0.01)
                    if State.currentRod and State.currentRod.Parent then
                        Humanoid:EquipTool(State.currentRod)
                        task.wait(0.01)
                        -- Try to cast line
                        CastLine:FireServer()
                    end
                    
                    State.isReeling = false
                end
            end
        end
    },
    
    simple = {
        name = "Simple Implementation",
        description = "Basic implementation with minimal complexity",
        instantReel = function(self)
            if State.isReeling then return end
            local reelUI = player.PlayerGui:FindFirstChild("reel")
            if reelUI then
                State.isReeling = true
                reelUI:Destroy()
                ReelFinished:FireServer(100, true)
                State.isReeling = false
            end
        end
    }
}

-- Helper Functions
local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local remainingSeconds = seconds % 60
    return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function calculateStats()
    local currentTime = os.time()
    local elapsedTime = currentTime - State.testStartTime
    local fishPerMinute = State.fishCaught / (elapsedTime / 60)
    return {
        duration = formatTime(elapsedTime),
        fishCount = State.fishCaught,
        fishPerMinute = string.format("%.2f", fishPerMinute)
    }
end

local function startTest()
    State.fishCaught = 0
    State.testStartTime = os.time()
    State.lastCatchTime = os.time()
    State.isAutoFishing = true
end

local function stopTest()
    State.isAutoFishing = false
    local stats = calculateStats()
    
    -- Save test results
    State.testResults[State.currentImplementation] = {
        fishCount = stats.fishCount,
        duration = stats.duration,
        fishPerMinute = stats.fishPerMinute,
        timestamp = os.date("%Y-%m-%d %H:%M:%S")
    }
end

-- Auto Fishing Functions
local function autoCast()
    if not State.isCasting and State.currentRod then
        State.isCasting = true
        CastLine:FireServer()
        task.wait(0.5)
        State.isCasting = false
    end
end

local function autoDropBobber()
    if not State.isDroppingBobber and State.currentRod then
        State.isDroppingBobber = true
        DropBobber:FireServer()
        task.wait(0.5)
        State.isDroppingBobber = false
    end
end

local function autoShake()
    if not State.isShaking and State.currentRod then
        State.isShaking = true
        ShakeRod:FireServer()
        task.wait(0.5)
        State.isShaking = false
    end
end

-- Create Window
local Window = Rayfield:CreateWindow({
    Name = "Fishing Implementation Tester",
    LoadingTitle = "Loading Tester...",
    LoadingSubtitle = "by Montrado",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "FishingTester",
        FileName = "Config"
    }
})

-- Create Tabs
local Tabs = {
    Main = Window:CreateTab("Testing", 4483362458),
    Results = Window:CreateTab("Results", 4483362458),
    Settings = Window:CreateTab("Settings", 4483362458)
}

-- Main Tab Elements
local implementationDropdown = Tabs.Main:CreateDropdown({
    Name = "Implementation",
    Options = {"default", "noxHub", "sasware", "enhanced", "simple"},
    CurrentOption = State.currentImplementation,
    Flag = "selectedImplementation",
    Callback = function(Value)
        State.currentImplementation = Value
    end,
})

local toggleButton = Tabs.Main:CreateToggle({
    Name = "Start Testing",
    CurrentValue = false,
    Flag = "testingToggle",
    Callback = function(Value)
        if Value then
            startTest()
        else
            stopTest()
        end
    end,
})

local statsLabel = Tabs.Main:CreateLabel("No test running")
local lastCatchLabel = Tabs.Main:CreateLabel("Last Catch Time: 0.00s")

-- Results Tab Elements
local resultsLabel = Tabs.Results:CreateLabel("No test results available")

-- Settings Tab Elements
Tabs.Settings:CreateSlider({
    Name = "Test Duration (minutes)",
    Range = {1, 30},
    Increment = 1,
    Suffix = "min",
    CurrentValue = State.testDuration / 60,
    Flag = "testDuration",
    Callback = function(Value)
        State.testDuration = Value * 60
    end,
})

-- Update Stats
RunService.Heartbeat:Connect(function()
    if State.isAutoFishing then
        local stats = calculateStats()
        local currentTime = os.time()
        local timeDiff = currentTime - State.lastCatchTime
        
        statsLabel:Set(string.format(
            "Duration: %s\nFish Caught: %d\nFish/min: %s",
            stats.duration,
            stats.fishCount,
            stats.fishPerMinute
        ))
        
        lastCatchLabel:Set(string.format("Last Catch Time: %.2fs", timeDiff))
        
        -- Auto-stop test if duration exceeded
        if currentTime - State.testStartTime >= State.testDuration then
            toggleButton:Set(false)
        end
    end
end)

-- Update Results Display
local function updateResults()
    local resultText = ""
    for impl, data in pairs(State.testResults) do
        resultText = resultText .. string.format(
            "\n[%s] %s\nFish: %d | Duration: %s | Fish/min: %s\n",
            data.timestamp,
            Implementations[impl].name,
            data.fishCount,
            data.duration,
            data.fishPerMinute
        )
    end
    
    if resultText == "" then
        resultText = "No test results available"
    end
    
    resultsLabel:Set(resultText)
end

-- Main Fishing Loop
task.spawn(function()
    while task.wait(0.01) do
        if State.isAutoFishing then
            -- Update current rod
            if Character then
                local tool = Character:FindFirstChildOfClass("Tool")
                if tool then
                    State.currentRod = tool
                end
            end
            
            -- Auto fishing sequence
            if State.currentRod then
                -- Check if we need to cast
                if not State.isCasting and not State.isReeling then
                    autoCast()
                end
                
                -- Check if we need to drop bobber
                if not State.isDroppingBobber and not State.isReeling then
                    autoDropBobber()
                end
                
                -- Check if we need to shake
                if not State.isShaking and not State.isReeling then
                    autoShake()
                end
                
                -- Try instant reel if available
                local currentImpl = Implementations[State.currentImplementation]
                if currentImpl then
                    currentImpl:instantReel()
                    State.fishCaught = State.fishCaught + 1
                    State.lastCatchTime = os.time()
                    updateResults()
                end
            end
        end
    end
end)

-- Character respawn handling
player.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
    Humanoid = newCharacter:WaitForChild("Humanoid")
    State.currentRod = nil
end)

-- Notify on load
Rayfield:Notify({
    Title = "Fishing Implementation Tester",
    Content = "Successfully loaded! Select an implementation to begin testing.",
    Duration = 3.5,
}) 