local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/aksaraax/Sedid-Helper/main/WindUI/main.luau"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CarRemotes = Remotes:WaitForChild("Car")

local Window = WindUI:CreateWindow({
	Title = "Aksara Studios",
	Folder = "aksarastudios_drift36",
	Icon = "rbxassetid://86369407133802",
	NewElements = true,
	Sidebar = {
		Icon = "rbxassetid://86369407133802",
		Version = "v0.0.4",
	},
	OpenButton = {
		Title = "D36",
		CornerRadius = UDim.new(0.5, 0),
		StrokeThickness = 2,
		Enabled = true,
		Draggable = true,
		OnlyMobile = false,
		Scale = 0.5,
		Color = ColorSequence.new(
			Color3.fromHex("#FFFFFF"),
			Color3.fromHex("#CCCCCC")
		)
	},
	Topbar = {
		Height = 44,
		ButtonsType = "Mac",
	},
})

Window:Tag({
	Title = "v0.0.4",
	Icon = "github",
	Color = Color3.fromHex("#1c1c1c"),
	Border = true,
})


local AutofarmModule = {}
local autofarmEnabled = false
local autofarmThread = nil

local RaceRemotes = Remotes:WaitForChild("Race")
local RaceEvent = RaceRemotes:WaitForChild("RaceEvent")

local SOLO_RACE_CHECKPOINTS = {
	start = Vector3.new(1010.9, 3.3, -764.6),
	checkpoints = {
		Vector3.new(1021.9, 10.8, -388.3),
		Vector3.new(1021.7, 11.0, 1.8),
		Vector3.new(605.6, 10.7, 225.0),
		Vector3.new(474.8, 10.7, 380.7),
		Vector3.new(471.5, 10.7, 770.5),
		Vector3.new(358.6, 10.9, 1010.3),
		Vector3.new(23.8, 10.6, 1010.3),
		Vector3.new(-296.2, 10.7, 1010.5),
		Vector3.new(-423.1, 10.8, 884.9),
		Vector3.new(-423.3, 10.9, 414.9),
		Vector3.new(-423.2, 11.8, -10.3),
		Vector3.new(-423.5, 11.7, -525.6),
	},
	finish = Vector3.new(-423.6, 10.6, -804.2),
	waitingZone = Vector3.new(940, 3, -695),
}

local function teleportCarToPos(position, yOffset)
	local character = LocalPlayer.Character
	if not character then return false end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return false end
	local seat = humanoid.SeatPart
	if not seat then return false end
	
	local car = nil
	local araclar = workspace:FindFirstChild("Araclar")
	if araclar then
		for _, c in araclar:GetChildren() do
			if c:IsA("Model") then
				for _, desc in c:GetDescendants() do
					if desc == seat then
						car = c
						break
					end
				end
			end
		end
	end
	
	if not car then return false end
	
	local currentCF = car:GetPivot()
	local newPos = Vector3.new(position.X, position.Y + (yOffset or 3), position.Z)
	local _, ry, _ = currentCF:ToEulerAnglesYXZ()
	local newCF = CFrame.new(newPos) * CFrame.Angles(0, ry, 0)
	
	car:PivotTo(newCF)
	return true
end

local function enterRaceZone()
	pcall(function()
		RaceEvent:FireServer({ action = "EnterRaceZone", raceId = "SoloRace" })
	end)
end

local function leaveRaceZone()
	pcall(function()
		RaceEvent:FireServer({ action = "LeaveRaceZone", raceId = "SoloRace" })
	end)
end

local function deleteCurrentCar()
	pcall(function()
		CarRemotes:WaitForChild("DeleteCar"):FireServer(LocalPlayer)
	end)
end

local function respawnCarAtRace(carModel)
	deleteCurrentCar()
	task.wait(1)
	
	local spawnPos = SOLO_RACE_CHECKPOINTS.waitingZone
	pcall(function()
		CarRemotes:WaitForChild("SpawnCar"):FireServer(
			carModel or "m5e34",
			Vector3.new(spawnPos.X, spawnPos.Y, spawnPos.Z)
		)
	end)
	task.wait(2)
end

local function getPlayerCarModel()
	local cars = LocalPlayer:FindFirstChild("Cars")
	if cars then
		for _, carFolder in cars:GetChildren() do
			if carFolder:IsA("Folder") then
				return carFolder.Name
			end
		end
	end
	return "m5e34"
end

local currentCheckpoint = 0
local raceInProgress = false
local countdownNumber = 99
local countdownFinished = false
local checkpointConnection = nil

local function setupRaceEventListener()
	if checkpointConnection then
		checkpointConnection:Disconnect()
	end
	
	checkpointConnection = RaceEvent.OnClientEvent:Connect(function(data)
		if typeof(data) == "table" then
			if data.type == "CheckpointPassed" then
				currentCheckpoint = data.checkpointNumber or data.current or 0
				print("[Autofarm] Checkpoint " .. currentCheckpoint .. "/" .. (data.total or 12) .. " passed!")
			elseif data.type == "PreCountdown" then
				local num = data.number or 0
				print("[Autofarm] PreCountdown: " .. num)
			elseif data.type == "Countdown" then
				countdownNumber = data.number or 0
				print("[Autofarm] Countdown: " .. countdownNumber)
				if countdownNumber <= 1 then
					countdownFinished = true
					raceInProgress = true
					print("[Autofarm] GO!")
				end
			elseif data.type == "RaceStarted" or data.type == "RaceStart" then
				raceInProgress = true
				countdownFinished = true
				currentCheckpoint = 0
				print("[Autofarm] Race started!")
			elseif data.type == "RaceFinished" or data.type == "RaceEnd" then
				raceInProgress = false
				print("[Autofarm] Race finished!")
			end
		end
	end)
end

function AutofarmModule.startRaceAutofarm(delay)
	if autofarmEnabled then return false, "Already running!" end
	autofarmEnabled = true
	local completedRaces = 0
	delay = delay or 0.5
	
	setupRaceEventListener()
	
	autofarmThread = task.spawn(function()
		print("[Autofarm] === STARTED ===")
		
		while autofarmEnabled do
			currentCheckpoint = 0
			
			print("[Autofarm] Step 1: Teleporting to waiting zone...")
			teleportCarToPos(SOLO_RACE_CHECKPOINTS.waitingZone, 3)
			task.wait(0.5)
			if not autofarmEnabled then break end
			
			print("[Autofarm] Step 2: Entering race zone...")
			enterRaceZone()
			task.wait(0.5)
			if not autofarmEnabled then break end
			
			print("[Autofarm] Step 3: Waiting for loading...")
			local loadingModule = LocalPlayer.PlayerGui:WaitForChild("General", 5)
			local loadingGui = loadingModule and loadingModule:WaitForChild("Modules", 5) and loadingModule.Modules:WaitForChild("loading", 5)
			
			if loadingGui then
				local waitAppear = 0
				while not loadingGui.Visible and waitAppear < 5 and autofarmEnabled do
					task.wait(0.1)
					waitAppear = waitAppear + 0.1
				end
				
				if loadingGui.Visible then
					print("[Autofarm] Loading screen detected!")
					local waitDisappear = 0
					while loadingGui.Visible and waitDisappear < 20 and autofarmEnabled do
						task.wait(0.2)
						waitDisappear = waitDisappear + 0.2
					end
					print("[Autofarm] Loading finished!")
				end
			end
			
			if not autofarmEnabled then break end
			
			print("[Autofarm] Step 4: Teleporting to start...")
			teleportCarToPos(SOLO_RACE_CHECKPOINTS.start, 3)
			task.wait(0.5)
			if not autofarmEnabled then break end
			
			print("[Autofarm] Step 4b: Waiting for countdown...")
			local generalGui = LocalPlayer.PlayerGui:FindFirstChild("General")
			local modulesGui = generalGui and generalGui:FindFirstChild("Modules")
			local startedGui = modulesGui and modulesGui:FindFirstChild("started")
			
			if startedGui then
				local waitAppear = 0
				while not startedGui.Visible and waitAppear < 5 and autofarmEnabled do
					task.wait(0.1)
					waitAppear = waitAppear + 0.1
				end
				
				if startedGui.Visible then
					print("[Autofarm] Countdown detected!")
					local waitDisappear = 0
					while startedGui.Visible and waitDisappear < 15 and autofarmEnabled do
						task.wait(0.2)
						waitDisappear = waitDisappear + 0.2
					end
					print("[Autofarm] Countdown done!")
				else
					task.wait(5)
				end
			else
				task.wait(6)
			end
			
			if not autofarmEnabled then break end
			
			print("[Autofarm] Step 4c: Waiting for BIG countdown...")
			local countdownGui = LocalPlayer.PlayerGui:FindFirstChild("General")
			countdownGui = countdownGui and countdownGui:FindFirstChild("Modules")
			countdownGui = countdownGui and countdownGui:FindFirstChild("countdown")
			countdownGui = countdownGui and countdownGui:FindFirstChild("ImageLabel")
			countdownGui = countdownGui and countdownGui:FindFirstChild("TextLabel")
			
			if countdownGui then
				local waitAppear = 0
				while not countdownGui.Visible and waitAppear < 10 and autofarmEnabled do
					task.wait(0.1)
					waitAppear = waitAppear + 0.1
				end
				
				if countdownGui.Visible then
					print("[Autofarm] BIG countdown detected!")
					local waitDisappear = 0
					while countdownGui.Visible and waitDisappear < 10 and autofarmEnabled do
						task.wait(0.1)
						waitDisappear = waitDisappear + 0.1
					end
					print("[Autofarm] START!")
				else
					task.wait(5)
				end
			else
				task.wait(6)
			end
			
			if not autofarmEnabled then break end
			
			print("[Autofarm] Step 5: Racing through checkpoints...")
			for i, checkpoint in ipairs(SOLO_RACE_CHECKPOINTS.checkpoints) do
				if not autofarmEnabled then break end
				print("[Autofarm] Checkpoint " .. i .. "/12")
				teleportCarToPos(checkpoint, 2)
				task.wait(delay)
			end
			
			if not autofarmEnabled then break end
			
			print("[Autofarm] Step 6: Crossing finish line...")
			teleportCarToPos(SOLO_RACE_CHECKPOINTS.finish, 2)
			task.wait(1)
			
			completedRaces = completedRaces + 1
			print("[Autofarm] Race #" .. completedRaces .. " COMPLETED!")
			
			print("[Autofarm] Step 7: Leaving race zone...")
			leaveRaceZone()
			task.wait(2)
			
			print("[Autofarm] Step 8: Waiting for lobby to clear...")
			local raceBg = LocalPlayer.PlayerGui:FindFirstChild("SoloRace")
			raceBg = raceBg and raceBg:FindFirstChild("Background")
			local raceText = raceBg and raceBg:FindFirstChild("TextLabel")
			
			if raceText then
				local waitClear = 0
				while raceText.Visible and (raceText.Text:lower():find("progress") or raceText.Text:lower():find("race")) and waitClear < 30 and autofarmEnabled do
					task.wait(0.5)
					waitClear = waitClear + 0.5
				end
				if waitClear > 0 then
					print("[Autofarm] Lobby cleared!")
				end
			end
			
			task.wait(1)
		end
		
		autofarmEnabled = false
		print("[Autofarm] === STOPPED === Total: " .. completedRaces .. " races")
	end)
	
	return true, "Autofarm started!"
end

function AutofarmModule.stop()
	autofarmEnabled = false
	if autofarmThread then 
		task.cancel(autofarmThread) 
		autofarmThread = nil
	end
	if checkpointConnection then
		checkpointConnection:Disconnect()
		checkpointConnection = nil
	end
	return true, "Stopped!"
end


local AutofarmTab = Window:Tab({
	Title = "Autofarm",
	Icon = "dollar-sign",
	IconColor = Color3.fromHex("#00FF00"),
})

AutofarmTab:Paragraph({ Title = "Solo Race Autofarm", Desc = "Teleport through checkpoints to earn money!" })

local tpDelay = 0.5

AutofarmTab:Slider({
	Title = "Teleport Delay (sec)",
	Desc = "",
	Value = { Min = 0.1, Max = 2, Default = 0.5 },
	Callback = function(v) tpDelay = v end
})

AutofarmTab:Space()

AutofarmTab:Button({
	Title = "START AUTOFARM",
	Desc = "",
	Callback = function()
		if autofarmEnabled then
			WindUI:Notify({ Title = "Warning", Content = "Already running!", Duration = 2 })
			return
		end
		local success, msg = AutofarmModule.startRaceAutofarm(tpDelay)
		WindUI:Notify({
			Title = if success then "Started!" else "Failed",
			Content = msg,
			Duration = 3,
		})
	end
})

AutofarmTab:Button({
	Title = "STOP AUTOFARM",
	Callback = function()
		AutofarmModule.stop()
		WindUI:Notify({ Title = "Stopped", Content = "Autofarm stopped!", Duration = 2 })
	end
})

AutofarmTab:Space()

AutofarmTab:Button({
	Title = "Teleport to Race",
	Desc = "",
	Callback = function()
		local ok = teleportCarToPos(SOLO_RACE_CHECKPOINTS.waitingZone, 3)
		WindUI:Notify({
			Title = if ok then "Teleported!" else "Get in car first!",
			Duration = 2,
		})
	end
})

AutofarmTab:Button({
	Title = "Respawn Car at Race",
	Desc = "",
	Callback = function()
		WindUI:Notify({ Title = "Respawning...", Duration = 1 })
		local carModel = getPlayerCarModel()
		respawnCarAtRace(carModel)
		WindUI:Notify({
			Title = "Respawned!",
			Content = "Car: " .. carModel,
			Duration = 2,
		})
	end
})

AutofarmTab:Paragraph({ Title = "Tips", Desc = "Stay in car\nLower delay = faster\nMay get kicked if too fast" })


local InfoTab = Window:Tab({
	Title = "Info",
	Icon = "info",
	IconColor = Color3.fromHex("#FFFFFF"),
})

InfoTab:Paragraph({
	Title = "How to Use",
	Desc = "1. Spawn and enter a car\n2. Set teleport delay\n3. Click START AUTOFARM",
})

InfoTab:Space()

InfoTab:Button({
	Title = "Player Info",
	Desc = "",
	Callback = function()
		WindUI:Notify({
			Title = LocalPlayer.DisplayName,
			Content = string.format("Username: %s\nUserId: %d", LocalPlayer.Name, LocalPlayer.UserId),
			Duration = 3,
		})
	end
})

InfoTab:Button({
	Title = "Server Info",
	Desc = "",
	Callback = function()
		local playerCount = #Players:GetPlayers()
		WindUI:Notify({
			Title = "Server Info",
			Content = string.format("Players: %d\nPlaceId: %d", playerCount, game.PlaceId),
			Duration = 3,
		})
	end
})


task.spawn(function()
	task.wait(1)
	WindUI:Notify({
		Title = "Aksara Studios",
		Content = "Drift 36 Helper v0.0.4",
		Duration = 3,
	})
end)

return Window
