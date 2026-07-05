local AdaptiveSong = {}
AdaptiveSong.__index = AdaptiveSong

local RunService = game:GetService("RunService")
local SongDataFolder = script.Parent:WaitForChild("SongData")

local Types = require(script.Parent.Types)
local Conductor = require(script.Parent.Conductor)
local Signal = require(script.Parent.Signal)

type StemData = Types.StemData
type SongData = Types.SongData

local function getSongData(songName: string): SongData?
	local songDataModule = SongDataFolder:FindFirstChild(songName)
	if not songDataModule then
		warn("Song data module not found for: " .. songName)
		return nil
	end

	local songData = require(songDataModule)
	assert(typeof(songData) == "table", "Song data must be a table for: " .. songName)

	return songData :: SongData
end

function AdaptiveSong.new(songName: string, yieldUntilLoaded: boolean)
	local self = setmetatable({}, AdaptiveSong)
	self.songData = getSongData(songName)
	self.songName = songName
	self.loaded = false
	self.conductor = nil

	self.NewStep = Signal.new()
	self.NewBeat = Signal.new()
	self.NewMeasure = Signal.new()

	assert(self.songData, "Failed to retrieve song data for: " .. songName)

	self.stems = {}
	self:_init(yieldUntilLoaded)

	return self
end

function AdaptiveSong:IsPlaying()
	return self.conductor and self.conductor.isPlaying
end

function AdaptiveSong:_init(yieldUntilLoaded: boolean)
	local soundDataFolder = Instance.new("Folder", workspace)
	soundDataFolder.Name = self.songName .. "_Stems"
	self.soundDataFolder = soundDataFolder

	-- Load each stem from song data
	for stemName: string, stemData: StemData in pairs(self.songData.Stems) do
		local sound = Instance.new("Sound")
		sound.SoundId = stemData.SoundId
		sound.Volume = stemData.Volume
		sound.PlaybackSpeed = self.songData.IntendedPlaybackSpeed
		sound.Name = stemName
		sound.Parent = soundDataFolder
		-- sound.SoundGroup = game:GetService("SoundService").Music

		self.stems[stemName] = sound

		if yieldUntilLoaded then
			if not sound.IsLoaded then
				sound.Loaded:Wait()
			end

			assert(sound.IsLoaded, "Failed to load stem: " .. stemName)
		end
	end

	self.loaded = true

	-- Create conductor
	self.conductor = Conductor.new(self.songData, self.stems, false)

	self.conductor.NewBeat:Connect(function(curBeat: number)
		self.NewBeat:Fire(curBeat)
	end)

	self.conductor.NewStep:Connect(function(curStep: number)
		self.NewStep:Fire(curStep)
	end)

	self.conductor.NewMeasure:Connect(function(curMeasure: number)
		self.NewMeasure:Fire(curMeasure)
	end)
end

function AdaptiveSong:YieldUntilLoaded()
	if self.loaded then
		return
	end

	while RunService.RenderStepped:Wait() do
		if self.loaded then
			break
		end
	end
end

function AdaptiveSong:Play()
	if self:IsPlaying() then
		return
	end

	print("Playing song: " .. self.songName)

	for name, stemData: Types.StemData in pairs(self.songData.Stems) do
		local volume = stemData.Volume
		local sound = self.stems[name]
		sound.Volume = volume
	end

	if not self.loaded then
		self:YieldUntilLoaded()
	end

	self.NewBeat:Fire(0)
	self.NewStep:Fire(0)
	self.NewMeasure:Fire(0)

	self.conductor:Play()
end

function AdaptiveSong:Resume()
	self.conductor:Resume()
end

function AdaptiveSong:Pause()
	self.conductor:Pause()
end

function AdaptiveSong:Stop(instant: boolean)
	if not self:IsPlaying() then
		return
	end

	print("Stopping song: " .. self.songName)
	self.conductor:Stop(instant)
end

--- FIXME: Causes desync on interrupted playback speed
-- function AdaptiveSong:SetPlaybackSpeed(speed: number)
-- 	self.conductor:SetPlaybackSpeed(speed)
-- end

--- FIXME: Causes desync on interrupted playback speed
-- function AdaptiveSong:TweenPlaybackSpeed(targetSpeed: number, duration: number)
-- 	self.conductor:TweenPlaybackSpeed(targetSpeed, duration)
-- end

function AdaptiveSong:SetMasterVolume(volume: number)
	self.conductor:SetMasterVolume(volume)
end

function AdaptiveSong:FadeStem(stemName: string, targetVolume: number, duration: number)
	self.conductor:FadeStem(stemName, targetVolume, duration)
end

function AdaptiveSong:SetStemVolume(stemName: string, volume: number)
	self.conductor:SetStemVolume(stemName, volume)
end

function AdaptiveSong:FadeStemOnNextSection(stemName: string, targetVolume: number, fadeDuration: number?)
	self.conductor:FadeStemOnNextSection(stemName, targetVolume, fadeDuration)
end

function AdaptiveSong:ScheduleFadeInBeats(
	beatCount: number,
	stemName: string,
	targetVolume: number,
	fadeDuration: number?
)
	self.conductor:ScheduleFadeInBeats(beatCount, stemName, targetVolume, fadeDuration)
end

function AdaptiveSong:ScheduleFadeInSections(
	sectionCount: number,
	stemName: string,
	targetVolume: number,
	fadeDuration: number?
)
	self.conductor:ScheduleFadeInSections(sectionCount, stemName, targetVolume, fadeDuration)
end

function AdaptiveSong:Destroy()
	self:Stop()
	self.stems = {}
	self.soundDataFolder:Destroy()
end

return AdaptiveSong
