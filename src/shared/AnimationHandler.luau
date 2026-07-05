local AnimationHandler = {}
AnimationHandler.__index = AnimationHandler

export type AnimationHandler = {
	Character: Model,
	Animator: Animator,
	Animations: { [string]: AnimationTrack },
}

function AnimationHandler.new(character: Model): AnimationHandler
	local self = setmetatable({}, AnimationHandler)

	self.Character = character

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	self.Animator = humanoid and humanoid.Animator or nil
	self.Animations = {}

	return self
end

function AnimationHandler:LoadAnimation(id: string, name: string): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = id

	local track = self.Animator:LoadAnimation(animation)
	track.Name = name
	self.Animations[name] = track

	return track
end

function AnimationHandler:LoadAnimationById(id: number, name: string): AnimationTrack?
	return self:LoadAnimation(`rbxassetid://{id}`, name)
end

function AnimationHandler:Play(name: string, fadeTime: number?, weight: number?, speed: number?): AnimationTrack?
	local track = self.Animations[name]
	if track then
		track:Play(fadeTime, weight, speed)
	end

	return track
end

function AnimationHandler:Stop(name: string, fadeTime: number?)
	local track = self.Animations[name]
	if track then
		track:Stop(fadeTime)
	end
end

function AnimationHandler:UnloadAll()
	for _, track in self.Animations do
		if track.Name == "Idle" then
			continue
		end

		track:Stop(0)
		track:Destroy()
	end

	self.Animations = {}
end

function AnimationHandler:StopAll(fadeTime: number?)
	for _, track in self.Animations do
		if track.Name == "Idle" then
			continue
		end
		track:Stop(fadeTime)
	end
end

function AnimationHandler:GetTrack(name: string): AnimationTrack?
	return self.Animations[name]
end

function AnimationHandler:Destroy()
	for _, track in self.Animations do
		track:Stop(0)
		track:Destroy()
	end

	self.Animations = {}
	self.Animator = nil
	self.Character = nil
end

return AnimationHandler
