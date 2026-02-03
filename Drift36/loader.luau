local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/aksaraax/Sedid-Helper/main/WindUI/main.luau"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CarRemotes = Remotes:WaitForChild("Car")

local ConfigManager = {}

local CONFIG_FOLDER = "aksarastudios_drift36"
local CONFIG_FILE = CONFIG_FOLDER .. "/config.json"

local defaultConfig = {
	performance = {
		hpMultiplier = 1,
		weightMultiplier = 1,
		finalDriveMultiplier = 1,
		maxUpgrades = false,
	},
}

local currentConfig = nil

local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local function mergeConfig(base, override)
	local result = deepCopy(base)
	for k, v in pairs(override) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = mergeConfig(result[k], v)
		else
			result[k] = v
		end
	end
	return result
end

local function ensureFolder()
	if not isfolder then return false end
	if not isfolder(CONFIG_FOLDER) then
		makefolder(CONFIG_FOLDER)
	end
	return true
end

function ConfigManager.load()
	if not isfile or not readfile then
		currentConfig = deepCopy(defaultConfig)
		return currentConfig
	end
	ensureFolder()
	if isfile(CONFIG_FILE) then
		local success, data = pcall(function()
			return HttpService:JSONDecode(readfile(CONFIG_FILE))
		end)
		if success and data then
			currentConfig = mergeConfig(defaultConfig, data)
			return currentConfig
		end
	end
	currentConfig = deepCopy(defaultConfig)
	return currentConfig
end

function ConfigManager.save()
	if not writefile then return false end
	if not currentConfig then return false end
	ensureFolder()
	local success = pcall(function()
		writefile(CONFIG_FILE, HttpService:JSONEncode(currentConfig))
	end)
	return success
end

function ConfigManager.get(path)
	if not currentConfig then ConfigManager.load() end
	local parts = string.split(path, ".")
	local current = currentConfig
	for _, part in ipairs(parts) do
		if type(current) ~= "table" then return nil end
		current = current[part]
	end
	return current
end

function ConfigManager.set(path, value)
	if not currentConfig then ConfigManager.load() end
	local parts = string.split(path, ".")
	local current = currentConfig
	for i = 1, #parts - 1 do
		local part = parts[i]
		if type(current[part]) ~= "table" then
			current[part] = {}
		end
		current = current[part]
	end
	current[parts[#parts]] = value
	ConfigManager.save()
	return true
end

ConfigManager.load()


local PerformanceModifier = {}

local TURBO_MULTIPLIERS = {
	["none"] = 1,
	["normal"] = 1.2,
	["twin"] = 1.4,
	["big"] = 1.7,
}

local INTAKE_MULTIPLIERS = {
	["none"] = 1,
	["normal"] = 1.05,
	["big"] = 1.15,
}

local INTERCOOLER_MULTIPLIERS = {
	["none"] = 1,
	["normal"] = 1.03,
	["big"] = 1.08,
}

local ECU_FD_MULTIPLIERS = {
	["none"] = 1,
	["sport"] = 0.95,
	["race"] = 0.9,
	["drag"] = 0.87,
}

local originalTuneValues = {}
local isModified = false


local torqueBoostEnabled = false
local torqueMultiplier = 1
local speedBoostEnabled = false
local speedMultiplier = 1

local function getCurrentCar()
	local character = LocalPlayer.Character
	if not character then return nil end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end
	
	local seatPart = humanoid.SeatPart
	if not seatPart then return nil end
	
	
	local current = seatPart.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChild("A-Chassis Tune") then
			return current
		end
		current = current.Parent
	end
	
	
	local araclar = workspace:FindFirstChild("Araclar")
	if not araclar then
		
		araclar = workspace
	end
	
	
	for _, child in araclar:GetChildren() do
		if child:IsA("Model") and child:FindFirstChild("A-Chassis Tune") then
			local driveSeat = child:FindFirstChild("DriveSeat")
			if driveSeat then
				
				if driveSeat:IsA("VehicleSeat") and driveSeat.Occupant then
					if driveSeat.Occupant.Parent == character then
						return child
					end
				end
			end
			
			for _, desc in child:GetDescendants() do
				if (desc:IsA("VehicleSeat") or desc:IsA("Seat")) and desc.Occupant then
					if desc.Occupant.Parent == character then
						return child
					end
				end
			end
		end
	end
	
	
	for _, child in araclar:GetChildren() do
		if child:IsA("Model") then
			local carCustom = child:FindFirstChild("CarCustom")
			local aChassisTune = child:FindFirstChild("A-Chassis Tune")
			if carCustom or aChassisTune then
				
				for _, desc in child:GetDescendants() do
					if (desc:IsA("VehicleSeat") or desc:IsA("Seat")) and desc.Occupant then
						if desc.Occupant.Parent == character then
							return child
						end
					end
				end
			end
		end
	end
	
	return nil
end

local function getCarTune(car)
	if not car then return nil end
	local tuneModule = car:FindFirstChild("A-Chassis Tune")
	if not tuneModule then return nil end
	
	local success, tune = pcall(function()
		return require(tuneModule)
	end)
	
	if success then
		return tune
	end
	return nil
end


local boostThread = nil
local boostForce = nil
local boostAttachment = nil

local function startForceBoost(forceMultiplier, maxForce)
	torqueBoostEnabled = true
	local forcePower = (forceMultiplier or 2) * 50000 
	local maxForceCap = maxForce or 500000
	
	
	if boostThread then
		task.cancel(boostThread)
		boostThread = nil
	end
	
	
	if boostForce then
		boostForce:Destroy()
		boostForce = nil
	end
	if boostAttachment then
		boostAttachment:Destroy()
		boostAttachment = nil
	end
	
	boostThread = task.spawn(function()
		while torqueBoostEnabled do
			task.wait()
			
			local car = getCurrentCar()
			if not car then continue end
			
			local driveSeat = car:FindFirstChild("DriveSeat")
			if not driveSeat then continue end
			
			
			local tuneModule = car:FindFirstChild("A-Chassis Tune")
			local throttle = 0
			local currentSpeed = 0
			
			if tuneModule then
				local interface = tuneModule:FindFirstChild("A-Chassis Interface")
				if interface then
					local values = interface:FindFirstChild("Values")
					if values then
						local throttleVal = values:FindFirstChild("Throttle")
						if throttleVal then
							throttle = throttleVal.Value or 0
						end
						local velocityVal = values:FindFirstChild("Velocity")
						if velocityVal then
							currentSpeed = velocityVal.Value.Magnitude
						end
					end
				end
			end
			
			
			if not boostForce or not boostForce.Parent then
				
				boostAttachment = Instance.new("Attachment")
				boostAttachment.Name = "BoostAttachment"
				boostAttachment.Parent = driveSeat
				
				
				boostForce = Instance.new("VectorForce")
				boostForce.Name = "BoostForce"
				boostForce.Attachment0 = boostAttachment
				boostForce.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
				boostForce.ApplyAtCenterOfMass = true
				boostForce.Force = Vector3.new(0, 0, 0)
				boostForce.Parent = driveSeat
			end
			
			
			if throttle > 0.1 then
				
				local speedFactor = math.max(0, 1 - currentSpeed / 150) 
				local force = forcePower * throttle * speedFactor
				force = math.min(force, maxForceCap)
				
				
				boostForce.Force = Vector3.new(0, 0, -force)
			else
				boostForce.Force = Vector3.new(0, 0, 0)
			end
		end
	end)
end

local function stopForceBoost()
	torqueBoostEnabled = false
	
	if boostThread then
		task.cancel(boostThread)
		boostThread = nil
	end
	
	if boostForce then
		boostForce:Destroy()
		boostForce = nil
	end
	if boostAttachment then
		boostAttachment:Destroy()
		boostAttachment = nil
	end
end



local function saveOriginalValues(tune)
	if not tune then return end
	if originalTuneValues[tune] then return end
	
	originalTuneValues[tune] = {
		Horsepower = tune.Horsepower,
		OriginalHorsepower = tune.OriginalHorsepower or tune.Horsepower,
		Weight = tune.Weight,
		OriginalWeight = tune.OriginalWeight or tune.Weight,
		FinalDrive = tune.FinalDrive,
		OriginalFinalDrive = tune.OriginalFinalDrive or tune.FinalDrive,
		BrakeForce = tune.BrakeForce,
	}
end

local function restoreOriginalValues(tune)
	if not tune then return end
	local original = originalTuneValues[tune]
	if not original then return end
	
	tune.Horsepower = original.Horsepower
	tune.Weight = original.Weight
	tune.FinalDrive = original.FinalDrive
	tune.BrakeForce = original.BrakeForce
end


local function getCarModelName()
	local cars = LocalPlayer:FindFirstChild("Cars")
	if not cars then return nil end
	
	for _, carFolder in cars:GetChildren() do
		if carFolder:IsA("Folder") then
			return carFolder.Name
		end
	end
	return nil
end


local function getCarModelFromCar(car)
	if not car then return nil end
	
	local carCustom = car:FindFirstChild("CarCustom")
	if carCustom then
		
		local carName = carCustom:FindFirstChild("carName")
		if carName and carName:IsA("StringValue") then
			return carName.Value
		end
	end
	
	
	local carFullName = car.Name
	local underscore = string.find(carFullName, "_")
	if underscore then
		return string.sub(carFullName, underscore + 1)
	end
	
	return nil
end


local ModifyCarRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Car"):WaitForChild("ModifyCar")

local function applyServerUpgrades(carModelName, upgradePreset)
	if not carModelName then
		return false, "Car model name not found!"
	end
	
	local upgrades = {
		
		turbo = {"turbo", "big", 0},
		intake = {"intake", "big", 0},
		intercooler = {"intercooler", "big", 0},
		ecu = {"ecu", "drag", 0},
	}
	
	if upgradePreset == "max" then
		
		for _, upgrade in pairs(upgrades) do
			pcall(function()
				ModifyCarRemote:FireServer(carModelName, "tune", upgrade[1], upgrade[2], upgrade[3])
			end)
			task.wait(0.1) 
		end
		return true, "Max upgrades applied!"
	elseif upgradePreset == "turbo" then
		pcall(function()
			ModifyCarRemote:FireServer(carModelName, "tune", "turbo", "big", 0)
		end)
		return true, "Big turbo applied!"
	elseif upgradePreset == "reset" then
		
		for _, upgrade in pairs(upgrades) do
			pcall(function()
				ModifyCarRemote:FireServer(carModelName, "tune", upgrade[1], "none", 0)
			end)
			task.wait(0.1)
		end
		return true, "Upgrades reset!"
	end
	
	return false, "Unknown preset"
end

function PerformanceModifier.applyModifications(hpMult, weightMult, fdMult, maxUpgrades)
	local car = getCurrentCar()
	if not car then
		return false, "Kamu harus berada di dalam mobil!"
	end
	
	local tune = getCarTune(car)
	if not tune then
		return false, "Tidak dapat menemukan A-Chassis Tune!"
	end
	
	saveOriginalValues(tune)
	local original = originalTuneValues[tune]
	
	local baseHP = original.OriginalHorsepower or original.Horsepower
	local baseWeight = original.OriginalWeight or original.Weight
	local baseFD = original.OriginalFinalDrive or original.FinalDrive
	
	local finalHPMult = hpMult
	local finalFDMult = fdMult
	
	if maxUpgrades then
		finalHPMult = finalHPMult * TURBO_MULTIPLIERS["big"]
		finalHPMult = finalHPMult * INTAKE_MULTIPLIERS["big"]
		finalHPMult = finalHPMult * INTERCOOLER_MULTIPLIERS["big"]
		finalFDMult = finalFDMult * ECU_FD_MULTIPLIERS["drag"]
	end
	
	local newHP = baseHP * finalHPMult
	local newWeight = baseWeight * weightMult
	local newFD = baseFD * finalFDMult
	
	
	tune.Horsepower = newHP
	tune.OriginalHorsepower = baseHP
	tune.Weight = newWeight
	tune.OriginalWeight = baseWeight
	tune.FinalDrive = newFD
	tune.OriginalFinalDrive = baseFD
	
	
	if tune.BrakeForce then
		tune.BrakeForce = newWeight * 2
	end
	
	if tune.RevAccel then
		tune.RevAccel = (tune.RevAccel or 250) * math.max(1, hpMult / 2)
	end
	if tune.ThrotAccel then
		tune.ThrotAccel = math.min(1, (tune.ThrotAccel or 0.1) * hpMult)
	end
	
	
	local tuneModule = car:FindFirstChild("A-Chassis Tune")
	if tuneModule then
		local aInterface = tuneModule:FindFirstChild("A-Chassis Interface")
		if aInterface then
			local values = aInterface:FindFirstChild("Values")
			if values then
				
				for _, valueObj in values:GetChildren() do
					if valueObj:IsA("NumberValue") or valueObj:IsA("IntValue") then
						if valueObj.Name == "Horsepower" or valueObj.Name == "HP" then
							valueObj.Value = newHP
						elseif valueObj.Name == "FinalDrive" or valueObj.Name == "FD" then
							valueObj.Value = newFD
						elseif valueObj.Name == "Weight" then
							valueObj.Value = newWeight * 0.453592 
						end
					end
				end
			end
			
			
			local driveScript = aInterface:FindFirstChild("Drive")
			if driveScript and driveScript:IsA("LocalScript") then
				
				local wasEnabled = driveScript.Enabled
				if wasEnabled then
					driveScript.Enabled = false
					task.wait(0.1)
					driveScript.Enabled = true
				end
			end
		end
	end
	
	
	for _, desc in car:GetDescendants() do
		if desc:IsA("NumberValue") then
			if desc.Name == "Horsepower" or desc.Name == "HP" then
				desc.Value = newHP
			elseif desc.Name == "Torque" or desc.Name == "MaxTorque" then
				desc.Value = newHP * 5 
			end
		end
	end
	
	if maxUpgrades then
		local carModelName = getCarModelFromCar(car)
		if carModelName then
			local success, msg = applyServerUpgrades(carModelName, "max")
			if success then
				isModified = true
				return true, string.format("SERVER UPGRADES APPLIED!\nCar: %s\n⚠️ Respawn mobil untuk efek!", carModelName)
			end
		else
			return false, "Tidak dapat menemukan nama model mobil!"
		end
	end
	
	isModified = true
	return true, "Modifications saved (client-side only)"
end


function PerformanceModifier.applyMaxUpgrades()
	local car = getCurrentCar()
	if not car then
		return false, "Kamu harus berada di dalam mobil!"
	end
	
	local carModelName = getCarModelFromCar(car)
	if not carModelName then
		return false, "Tidak dapat menemukan nama model mobil!"
	end
	
	local success, msg = applyServerUpgrades(carModelName, "max")
	if success then
		isModified = true
		return true, string.format("MAX UPGRADES APPLIED!\nCar: %s\n\n⚠️ RESPAWN MOBIL untuk melihat efek!\n(Kembali ke garage dan spawn ulang)", carModelName)
	end
	return false, msg
end

function PerformanceModifier.resetModifications()
	local car = getCurrentCar()
	if not car then
		return false, "Kamu harus berada di dalam mobil!"
	end
	
	local tune = getCarTune(car)
	if not tune then
		return false, "Tidak dapat menemukan A-Chassis Tune!"
	end
	
	restoreOriginalValues(tune)
	
	
	stopForceBoost()
	
	isModified = false
	return true, "Boost disabled! Stats reset."
end

function PerformanceModifier.getCarStats()
	local car = getCurrentCar()
	if not car then
		return nil
	end
	
	local tune = getCarTune(car)
	if not tune then
		return nil
	end
	
	return {
		name = car.Name,
		hp = tune.Horsepower or 0,
		weight = tune.Weight or 0,
		finalDrive = tune.FinalDrive or 0,
		redline = tune.Redline or 0,
		config = tune.Config or "RWD",
	}
end


local Window = WindUI:CreateWindow({
	Title = "Aksara Studios  ",
	Folder = "aksarastudios_drift36",
	Icon = "rbxassetid://86369407133802",
	NewElements = true,
	Sidebar = {
		Icon = "rbxassetid://86369407133802  ",
		Version = "v0.0.3",
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
	Title = "v0.0.3",
	Icon = "github",
	Color = Color3.fromHex("#1c1c1c"),
	Border = true,
})


local PerformanceTab = Window:Tab({
	Title = "Performance",
	Icon = "rocket",
	IconColor = Color3.fromHex("#FF6B6B"),
})

PerformanceTab:Paragraph({ Title = "🏎️ Car Stats", Desc = "" })

local carStatsParagraph = PerformanceTab:Paragraph({
	Title = "Current Car",
	Desc = "Not in a car",
})

PerformanceTab:Button({
	Title = "Refresh Stats",
	Desc = "",
	Callback = function()
		local stats = PerformanceModifier.getCarStats()
		if stats then
			carStatsParagraph:SetTitle(stats.name)
			carStatsParagraph:SetDesc(string.format(
				"HP: %.0f | Weight: %.0f\nFD: %.2f | Redline: %d\nDrivetrain: %s",
				stats.hp, stats.weight, stats.finalDrive, stats.redline, stats.config
			))
		else
			carStatsParagraph:SetTitle("Current Car")
			carStatsParagraph:SetDesc("Not in a car")
		end
	end
})

PerformanceTab:Space()
PerformanceTab:Paragraph({ Title = "⚡ Acceleration Modifiers", Desc = "" })

local hpMultiplier = ConfigManager.get("performance.hpMultiplier") or 1
local weightMultiplier = ConfigManager.get("performance.weightMultiplier") or 1
local fdMultiplier = ConfigManager.get("performance.finalDriveMultiplier") or 1
local maxUpgradesEnabled = ConfigManager.get("performance.maxUpgrades") or false

PerformanceTab:Slider({
	Title = "HP Multiplier",
	Desc = "",
	Value = {
		Min = 1,
		Max = 10,
		Default = hpMultiplier,
	},
	Callback = function(value)
		hpMultiplier = value
		ConfigManager.set("performance.hpMultiplier", value)
	end
})

PerformanceTab:Slider({
	Title = "Weight Multiplier",
	Desc = "",
	Value = {
		Min = 0.1,
		Max = 1,
		Default = weightMultiplier,
	},
	Callback = function(value)
		weightMultiplier = value
		ConfigManager.set("performance.weightMultiplier", value)
	end
})

PerformanceTab:Slider({
	Title = "Final Drive Multiplier",
	Desc = "",
	Value = {
		Min = 0.5,
		Max = 1.5,
		Default = fdMultiplier,
	},
	Callback = function(value)
		fdMultiplier = value
		ConfigManager.set("performance.finalDriveMultiplier", value)
	end
})

PerformanceTab:Toggle({
	Title = "Max Upgrades",
	Desc = "",
	Value = maxUpgradesEnabled,
	Callback = function(value)
		maxUpgradesEnabled = value
		ConfigManager.set("performance.maxUpgrades", value)
	end
})

PerformanceTab:Space()
PerformanceTab:Paragraph({ Title = "⚡ Server-Side Upgrades", Desc = "These upgrades are REAL and persist!" })

PerformanceTab:Button({
	Title = "🚀 APPLY MAX UPGRADES (SERVER)",
	Desc = "",
	Callback = function()
		WindUI:Notify({ Title = "Processing", Content = "Sending to server...", Duration = 1 })
		
		local success, msg = PerformanceModifier.applyMaxUpgrades()
		
		WindUI:Notify({
			Title = if success then "✅ SUCCESS!" else "❌ Failed",
			Content = msg,
			Duration = 5,
		})
	end
})

PerformanceTab:Space()
PerformanceTab:Paragraph({ Title = "🔧 Client-Side Mods", Desc = "These only affect your view" })

PerformanceTab:Button({
	Title = "Apply Modifications (Client)",
	Desc = "",
	Callback = function()
		WindUI:Notify({ Title = "Processing", Content = "Applying modifications...", Duration = 1 })
		
		local success, msg = PerformanceModifier.applyModifications(
			hpMultiplier,
			weightMultiplier,
			fdMultiplier,
			maxUpgradesEnabled
		)
		
		WindUI:Notify({
			Title = if success then "Success" else "Failed",
			Content = msg,
			Duration = 3,
		})
	end
})

PerformanceTab:Button({
	Title = "Reset Modifications",
	Desc = "",
	Callback = function()
		local success, msg = PerformanceModifier.resetModifications()
		WindUI:Notify({
			Title = if success then "Success" else "Failed",
			Content = msg,
			Duration = 2,
		})
	end
})


local PresetsTab = Window:Tab({
	Title = "Presets",
	Icon = "zap",
	IconColor = Color3.fromHex("#FFD700"),
})

PresetsTab:Paragraph({ Title = "🚀 SERVER-SIDE PRESETS", Desc = "These upgrades are REAL and saved to your account!" })

PresetsTab:Button({
	Title = "🔥 MAX UPGRADES (FREE)",
	Desc = "",
	Callback = function()
		WindUI:Notify({ Title = "⏳ Processing", Content = "Sending upgrades to server...", Duration = 2 })
		
		local success, msg = PerformanceModifier.applyMaxUpgrades()
		WindUI:Notify({
			Title = if success then "✅ SUCCESS!" else "❌ Failed",
			Content = msg,
			Duration = 5,
		})
	end
})

PresetsTab:Space()
PresetsTab:Paragraph({ Title = "ℹ️ Instructions", Desc = "1. Click MAX UPGRADES\n2. Wait for success message\n3. Go back to garage\n4. Respawn your car\n5. Enjoy MAX POWER! 🚗💨" })

PresetsTab:Button({
	Title = "🎯 Drift King",
	Desc = "",
	Callback = function()
		local success, msg = PerformanceModifier.applyModifications(3, 0.6, 0.9, true)
		WindUI:Notify({
			Title = if success then "Drift King Applied" else "Failed",
			Content = msg,
			Duration = 2,
		})
	end
})

PresetsTab:Space()

PresetsTab:Button({
	Title = "🔄 Reset to Stock",
	Desc = "",
	Callback = function()
		local success, msg = PerformanceModifier.resetModifications()
		WindUI:Notify({
			Title = if success then "Reset Complete" else "Failed",
			Content = msg,
			Duration = 2,
		})
	end
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

local AutofarmModule = {}
local autofarmEnabled = false
local autofarmThread = nil
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
				print("[Autofarm] ✓ Checkpoint " .. currentCheckpoint .. "/" .. (data.total or 12) .. " passed!")
			
			
			elseif data.type == "PreCountdown" then
				local num = data.number or 0
				print("[Autofarm] 📍 PreCountdown: " .. num)
				
				if num <= 1 then
					print("[Autofarm] 📍 PreCountdown finished! Moving to start...")
				end
			
			
			elseif data.type == "Countdown" then
				countdownNumber = data.number or 0
				print("[Autofarm] ⏱️ Countdown: " .. countdownNumber)
				if countdownNumber <= 1 then
					countdownFinished = true
					raceInProgress = true
					print("[Autofarm] 🏁 GO! Race starting!")
				end
			
			
			elseif data.type == "RaceStarted" or data.type == "RaceStart" then
				raceInProgress = true
				countdownFinished = true
				currentCheckpoint = 0
				print("[Autofarm] 🏁 Race started!")
			
			
			elseif data.type == "RaceFinished" or data.type == "RaceEnd" then
				raceInProgress = false
				print("[Autofarm] 🏆 Race finished!")
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
		
		
		local loadingModule = LocalPlayer.PlayerGui:FindFirstChild("General")
		local loadingGui = loadingModule and loadingModule:FindFirstChild("Modules") and loadingModule.Modules:FindFirstChild("loading")
		
		while autofarmEnabled do
			
			currentCheckpoint = 0
			
			
			print("[Autofarm] Step 1: Teleporting to race waiting zone...")
			teleportCarToPos(SOLO_RACE_CHECKPOINTS.waitingZone, 3)
			task.wait(0.5)
			if not autofarmEnabled then break end
			
			
			print("[Autofarm] Step 2: Entering race zone...")
			enterRaceZone()
			task.wait(0.5)
			if not autofarmEnabled then break end
			
			
			print("[Autofarm] Step 3: Waiting for loading to finish...")
			
			
			local loadingModule = LocalPlayer.PlayerGui:WaitForChild("General", 5)
			local loadingGui = loadingModule and loadingModule:WaitForChild("Modules", 5) and loadingModule.Modules:WaitForChild("loading", 5)
			
			if loadingGui then
				
				local waitAppear = 0
				while not loadingGui.Visible and waitAppear < 5 and autofarmEnabled do
					task.wait(0.1)
					waitAppear = waitAppear + 0.1
				end
				
				if loadingGui.Visible then
					print("[Autofarm] Loading screen detected! Waiting for it to finish...")
					
					local waitDisappear = 0
					while loadingGui.Visible and waitDisappear < 20 and autofarmEnabled do
						task.wait(0.2)
						waitDisappear = waitDisappear + 0.2
					end
					print("[Autofarm] Loading finished! (" .. string.format("%.1f", waitDisappear) .. "s)")
				else
					print("[Autofarm] Loading screen didn't appear in time, proceeding...")
				end
			else
				print("[Autofarm] Loading GUI not found in PlayerGui.")
			end
			
			if not autofarmEnabled then break end
			
			
			print("[Autofarm] Step 4: Teleporting to start line...")
			teleportCarToPos(SOLO_RACE_CHECKPOINTS.start, 3)
			task.wait(0.5)
			if not autofarmEnabled then break end
			
			
			print("[Autofarm] Step 4b: Waiting for race start countdown...")
			
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
					print("[Autofarm] Countdown detected! Waiting for it to finish...")
					
					local waitDisappear = 0
					while startedGui.Visible and waitDisappear < 15 and autofarmEnabled do
						task.wait(0.2)
						waitDisappear = waitDisappear + 0.2
					end
					print("[Autofarm] Race started! Countdown done (" .. string.format("%.1f", waitDisappear) .. "s)")
				else
					print("[Autofarm] Countdown GUI did not appear, using safe wait...")
					task.wait(5)
				end
			else
				print("[Autofarm] Countdown GUI path invalid, using safe wait...")
				task.wait(6)
			end
			
			if not autofarmEnabled then break end
			
			
			print("[Autofarm] Step 4c: Waiting for BIG COUNTDOWN...")
			
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
					print("[Autofarm] BIG COUNTDOWN detected! Waiting for GO...")
					
					local waitDisappear = 0
					while countdownGui.Visible and waitDisappear < 10 and autofarmEnabled do
						task.wait(0.1)
						waitDisappear = waitDisappear + 0.1
						
						if math.floor(waitDisappear * 10) % 10 == 0 then
							print("[Autofarm] Countdown: " .. countdownGui.Text)
						end
					end
					print("[Autofarm] 🏁 START! (" .. string.format("%.1f", waitDisappear) .. "s)")
				else
					print("[Autofarm] Big Countdown GUI did not appear, using safe wait...")
					task.wait(5)
				end
			else
				print("[Autofarm] Big Countdown path invalid, using safe wait...")
				task.wait(6)
			end
			
			if not autofarmEnabled then break end
			
			
			print("[Autofarm] Step 5: GO! Racing through checkpoints...")
			
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
			print("[Autofarm] ✅ Race #" .. completedRaces .. " COMPLETED!")
			
			
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
					if math.floor(waitClear * 10) % 50 == 0 then
						print("[Autofarm] Waiting for 'Race in Progress' to clear...")
					end
				end
				if waitClear > 0 then
					print("[Autofarm] Lobby cleared! (" .. string.format("%.1f", waitClear) .. "s)")
				end
			else
				print("[Autofarm] Lobby GUI not found, proceeding...")
			end
			
			task.wait(1)
		end
		
		autofarmEnabled = false
		print("[Autofarm] === STOPPED === Total: " .. completedRaces .. " races")
	end)
	
	return true, "Timer-based autofarm started!"
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

AutofarmTab:Paragraph({ Title = "🏎️ Solo Race Autofarm", Desc = "Teleport through checkpoints to earn money!" })

local tpDelay = 0.5

AutofarmTab:Slider({
	Title = "Teleport Delay (sec)",
	Desc = "",
	Value = { Min = 0.1, Max = 2, Default = 0.5 },
	Callback = function(v) tpDelay = v end
})

AutofarmTab:Space()

AutofarmTab:Button({
	Title = "🚀 START AUTOFARM",
	Desc = "",
	Callback = function()
		if autofarmEnabled then
			WindUI:Notify({ Title = "⚠️", Content = "Already running!", Duration = 2 })
			return
		end
		local success, msg = AutofarmModule.startRaceAutofarm(tpDelay)
		WindUI:Notify({
			Title = if success then "✅ Started!" else "❌ Failed",
			Content = msg,
			Duration = 3,
		})
	end
})

AutofarmTab:Button({
	Title = "🛑 STOP AUTOFARM",
	Callback = function()
		AutofarmModule.stop()
		WindUI:Notify({ Title = "Stopped", Content = "Autofarm stopped!", Duration = 2 })
	end
})

AutofarmTab:Space()

AutofarmTab:Button({
	Title = "📍 Teleport to Race",
	Desc = "",
	Callback = function()
		local ok = teleportCarToPos(SOLO_RACE_CHECKPOINTS.waitingZone, 3)
		WindUI:Notify({
			Title = if ok then "✅ Teleported!" else "❌ Get in car!",
			Duration = 2,
		})
	end
})

AutofarmTab:Button({
	Title = "🔄 Respawn Car at Race",
	Desc = "",
	Callback = function()
		WindUI:Notify({ Title = "⏳", Content = "Respawning car...", Duration = 1 })
		local carModel = getPlayerCarModel()
		respawnCarAtRace(carModel)
		WindUI:Notify({
			Title = "✅ Respawned!",
			Content = "Car: " .. carModel,
			Duration = 2,
		})
	end
})

AutofarmTab:Paragraph({ Title = "⚠️ Tips", Desc = "• Stay in car\n• Lower delay = faster\n• May get kicked if too fast" })


local InfoTab = Window:Tab({
	Title = "Info",
	Icon = "info",
	IconColor = Color3.fromHex("#FFFFFF"),
})

InfoTab:Paragraph({
	Title = "📖 How to Use",
	Desc = "1. Spawn and enter a car\n2. Go to Performance tab\n3. Adjust sliders or use Presets\n4. Click Apply Modifications",
})

InfoTab:Space()

InfoTab:Paragraph({
	Title = "⚠️ Notes",
	Desc = "• Modifications are client-side only\n• Other players won't see your boosted stats\n• Re-apply after respawning car\n• Works with all A-Chassis cars",
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

InfoTab:Space()
InfoTab:Paragraph({ Title = "🔧 Debug Tools", Desc = "" })

InfoTab:Button({
	Title = "Debug Car Detection",
	Desc = "Find A-Chassis cars in Araclar",
	Callback = function()
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		local seatPart = humanoid and humanoid.SeatPart
		
		local debugInfo = {}
		table.insert(debugInfo, "SeatPart: " .. (seatPart and seatPart.Name or "nil"))
		
		if seatPart then
			table.insert(debugInfo, "Parent: " .. (seatPart.Parent and seatPart.Parent.Name or "nil"))
			
			local path = {}
			local current = seatPart
			while current and current ~= workspace do
				table.insert(path, 1, current.Name)
				current = current.Parent
			end
			table.insert(debugInfo, "Path: " .. table.concat(path, "/"))
		end
		
		
		local araclar = workspace:FindFirstChild("Araclar")
		table.insert(debugInfo, "Araclar: " .. (araclar and "FOUND" or "NOT FOUND"))
		
		local carCount = 0
		local searchFolder = araclar or workspace
		for _, child in searchFolder:GetChildren() do
			if child:IsA("Model") then
				local hasAChassis = child:FindFirstChild("A-Chassis Tune")
				local hasCarCustom = child:FindFirstChild("CarCustom")
				if hasAChassis or hasCarCustom then
					carCount = carCount + 1
					table.insert(debugInfo, "Car: " .. child.Name)
				end
			end
		end
		
		table.insert(debugInfo, "Total Cars: " .. carCount)
		
		local car = PerformanceModifier.getCarStats() and "DETECTED" or "NOT DETECTED"
		table.insert(debugInfo, "Your Car: " .. car)
		
		WindUI:Notify({
			Title = "Debug Info",
			Content = table.concat(debugInfo, "\n"),
			Duration = 10,
		})
	end
})


task.spawn(function()
	task.wait(1)
	WindUI:Notify({
		Title = "Aksara Studios",
		Content = "Drift 36 Helper",
		Duration = 3,
	})
end)

return Window


