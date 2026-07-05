local Conductor = {}
Conductor.__index = Conductor

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)
local Signal = require(script.Parent.Signal)

local RESYNC_THRESHOLD = 0.05
local RESYNC_INTERVAL = 1
local LOOP_THRESHOLD = 0.03

function Conductor.new(songData: Types.SongData, stems: { [string]: Sound }, playMetronome: boolean)
	local self = setmetatable({}, Conductor)
	self.songData = songData
	self.stems = stems
	self.playMetronome = playMetronome

	self.curBeat = 0
	self.curStep = 0
	self.curMeasure = 0
	self.beatsPerMeasure = songData.StartingBeatsPerMeasure
	self.stepsPerBeat = 4
	self.bpm = songData.StartingBPM

	-- Pick master stem basic on length
	self.masterStem = nil
	local longestTime = 0

	for _, stem: Sound in pairs(stems) do
		if not stem.IsLoaded then
			stem.Loaded:Wait()
		end

		if stem.TimeLength >= longestTime then
			self.masterStem = stem
			longestTime = stem.TimeLength
		end
	end

	print("Master stem name:", self.masterStem)

	self.masterStem.Ended:Connect(function()
		if not self.songStopped then
			print(self.songData.Title, "loop")
			self:Stop()

			task.wait(1)

			self:Play()
		else
			warn(self.songStopped)
		end
	end)

	self.elapsedTime = 0
	self.resyncTimer = 0
	self.isPlaying = false
	self.songStopped = false
	self.songFinished = false
	self.resyncing = false

	self._scheduledFadeConnections = {}

	self.NewBeat = Signal.new()
	self.NewStep = Signal.new()
	self.NewMeasure = Signal.new()

	self.updateConnection = nil

	self.metronomeSound = Instance.new("Sound", script)
	self.metronomeSound.SoundId = "rbxassetid://126224146490525"
	self.metronomeSound.Volume = playMetronome and 1.0 or 0.0

	return self
end

function Conductor:SetPlaybackSpeed(speed: number)
	self.bpm = self.songData.StartingBPM * speed
	for _, stem in pairs(self.stems) do
		stem.PlaybackSpeed = speed
	end
end

function Conductor:SetMasterVolume(volume: number)
	for _, stem in pairs(self.stems) do
		stem.Volume = volume
	end
end

function Conductor:TweenPlaybackSpeed(targetSpeed: number, duration: number)
	local value = Instance.new("NumberValue", script)
	local valueTween = TweenService:Create(value, TweenInfo.new(duration), { Value = targetSpeed })
	value.Value = self.masterStem.PlaybackSpeed
	valueTween:Play()

	value:GetPropertyChangedSignal("Value"):Connect(function()
		self:SetPlaybackSpeed(value.Value)
	end)

	valueTween.Completed:Connect(function()
		value:Destroy()
	end)
end

function Conductor:_checkAndResync()
	local master = self.masterStem

	if not master.IsPlaying or self.resyncing then
		return
	end

	local masterTime = master.TimePosition

	for name, stem in pairs(self.stems) do
		if stem == master then
			continue
		end

		local difference = math.abs(stem.TimePosition - masterTime)

		if not stem.IsPlaying or difference > RESYNC_THRESHOLD then
			self.resyncing = true
			--warn(name, "stopped unexpectedly")

			-- we have to go nuclear and replay
			-- im sorry! i dont WANT to
			-- roblox's audio engine is genuinely that bad with mutli track playing
			self:Stop()

			task.wait(3)

			self:Play(nil, true) -- that little true tells the play "hey, im only playing to get back on track"
			-- with self.resyncing enabled, nothing can play it but this
			self.resyncing = false
		end
	end
end

function Conductor:_checkLoop()
	if self.songFinished then
		return
	end

	local master = self.masterStem

	if master.TimeLength <= 0 then
		return
	end

	local remaining = master.TimeLength - master.TimePosition

	if remaining <= LOOP_THRESHOLD then
		self.songFinished = true

		task.defer(function()
			self:Play(0)
		end)
	end
end

function Conductor:_tickBeats()
	local secondsPerBeat = 60 / self.bpm
	local secondsPerStep = secondsPerBeat / self.stepsPerBeat

	local newBeat = math.floor(self.elapsedTime / secondsPerBeat)
	local newStep = math.floor(self.elapsedTime / secondsPerStep)
	local newMeasure = math.floor(newBeat / self.beatsPerMeasure)

	if newBeat > self.curBeat then
		self.curBeat = newBeat
		self.NewBeat:Fire(self.curBeat)
		self.metronomeSound:Play()
	end

	if newStep > self.curStep then
		self.curStep = newStep
		self.NewStep:Fire(self.curStep)
	end

	if newMeasure > self.curMeasure then
		self.curMeasure = newMeasure
		self.NewMeasure:Fire(self.curMeasure)
	end
end

function Conductor:Update(dt)
	local master = self.masterStem

	if not master:IsDescendantOf(game) then
		return
	end

	if not master.IsPlaying then
		return
	end

	self.elapsedTime = master.TimePosition

	self:_tickBeats()

	self.resyncTimer += dt

	if self.resyncTimer >= RESYNC_INTERVAL then
		self.resyncTimer = 0

		self:_checkAndResync()
	end

	self:_checkLoop()
end

function Conductor:Play(startTime, isResyncing)
	if self.resyncing and not isResyncing then
		return
	end
	startTime = startTime or 0

	self.isPlaying = true
	self.songStopped = false
	self.songFinished = false

	self.curBeat = 0
	self.curStep = 0
	self.curMeasure = 0

	self.elapsedTime = startTime
	self.resyncTimer = 0

	local speed = self.masterStem.PlaybackSpeed

	for name, stem in pairs(self.stems) do
		stem:Stop()

		stem.Volume = self.songData.Stems[name].Volume

		stem.PlaybackSpeed = speed

		stem.TimePosition = startTime
	end

	task.wait()

	for _, stem in pairs(self.stems) do
		stem:Play()
	end

	if not self.updateConnection then
		self.updateConnection = RunService.Heartbeat:Connect(function(dt)
			self:Update(dt)
		end)
	end
end

function Conductor:Pause()
	self.songStopped = true
	self.isPlaying = false
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	for _, stem in pairs(self.stems) do
		stem:Pause()
	end
end

function Conductor:Resume()
	self.isPlaying = true
	self.songStopped = false

	-- Resync all stems to master before resuming to avoid accumulated drift
	local targetTime = self.elapsedTime

	for _, stem in pairs(self.stems) do
		stem.TimePosition = targetTime
		stem:Play()
	end

	if not self.updateConnection then
		self.updateConnection = RunService.Heartbeat:Connect(function(dt)
			self:Update(dt)
		end)
	end
end

function Conductor:Stop(instant: boolean)
	self.isPlaying = false
	self.songStopped = true

	for _, connection in pairs(self._scheduledFadeConnections) do
		connection:Disconnect()
	end
	self._scheduledFadeConnections = {}

	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	for _, stem in pairs(self.stems) do
		if instant then
			stem:Stop()
			stem.TimePosition = 0
		else
			local tween = TweenService:Create(stem, TweenInfo.new(1), { Volume = 0 })
			tween:Play()
			stem.Ended:Once(function()
				stem:Stop()
				stem.TimePosition = 0
			end)
		end
	end

	self.curBeat = 0
	self.curStep = 0
	self.curMeasure = 0
	self.elapsedTime = 0
	self.resyncTimer = 0
end

function Conductor:FadeStem(stemName: string, targetVolume: number, duration: number)
	local stem = self.stems[stemName]
	if stem then
		TweenService:Create(stem, TweenInfo.new(duration), { Volume = targetVolume }):Play()
	else
		warn("Stem not found: " .. stemName)
	end
end

function Conductor:ChangeStemVolume(stemName: string, newVolume: number)
	local stem = self.stems[stemName]
	if stem then
		stem.Volume = newVolume
	else
		warn("Stem not found: " .. stemName)
	end
end

function Conductor:ChangeBeatsPerMeasure(newBeatsPerMeasure: number)
	self.beatsPerMeasure = newBeatsPerMeasure
end

function Conductor:ChangeBPM(newBPM: number)
	self.bpm = newBPM
end

function Conductor:ChangePlaybackSpeed(newPlaybackSpeed: number)
	for _, stem in pairs(self.stems) do
		stem.PlaybackSpeed = newPlaybackSpeed
	end
end

function Conductor:FadeStemOnNextSection(stemName: string, targetVolume: number, fadeDuration: number?)
	if not self.stems[stemName] then
		warn("Stem not found: " .. stemName)
		return
	end

	local duration = fadeDuration or 1.0

	local connection
	connection = self.NewMeasure:Connect(function()
		connection:Disconnect()
		self._scheduledFadeConnections[connection] = nil
		self:FadeStem(stemName, targetVolume, duration)
	end)
	self._scheduledFadeConnections[connection] = connection
end

function Conductor:ScheduleFadeInBeats(beatCount: number, stemName: string, targetVolume: number, fadeDuration: number?)
	if not self.stems[stemName] then
		warn("Stem not found: " .. stemName)
		return
	end

	local duration = fadeDuration or 1.0
	local targetBeat = self.curBeat + beatCount

	local connection
	connection = self.NewBeat:Connect(function()
		if self.curBeat >= targetBeat then
			connection:Disconnect()
			self._scheduledFadeConnections[connection] = nil
			self:FadeStem(stemName, targetVolume, duration)
		end
	end)
	self._scheduledFadeConnections[connection] = connection
end

function Conductor:ScheduleFadeInSections(
	sectionCount: number,
	stemName: string,
	targetVolume: number,
	fadeDuration: number?
)
	if not self.stems[stemName] then
		warn("Stem not found: " .. stemName)
		return
	end

	local duration = fadeDuration or 1.0
	local targetMeasure = self.curMeasure + sectionCount

	local connection
	connection = self.NewMeasure:Connect(function()
		if self.curMeasure >= targetMeasure then
			connection:Disconnect()
			self._scheduledFadeConnections[connection] = nil
			self:FadeStem(stemName, targetVolume, duration)
		end
	end)
	self._scheduledFadeConnections[connection] = connection
end

function Conductor:Destroy()
	self:Stop()
	self.metronomeSound:Destroy()
	-- AdaptiveSong cleans up stems
end

return Conductor
