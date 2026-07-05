local StatsUI = {}
StatsUI.__index = StatsUI

type StatsUIOptions = {
	onExitRequested: (() -> ())?,
}

function StatsUI.new(statsGui: Instance?, options: StatsUIOptions?)
	local self = setmetatable({}, StatsUI)
	self.gui = statsGui
	self.started = false
	self.onExitRequested = if options then options.onExitRequested else nil
	self.exitButton = nil

	if self.gui then
		self.gui.Visible = false
		local exitButton = self.gui:FindFirstChild("Exit", true)
		if exitButton and exitButton:IsA("TextButton") then
			self.exitButton = exitButton
			exitButton.MouseButton1Click:Connect(function()
				self:RequestExit()
			end)
		end
	end

	return self
end

function StatsUI:Start()
	self.started = true
end

function StatsUI:Show()
	if self.gui then
		self.gui.Visible = true
	end
end

function StatsUI:Hide()
	if self.gui then
		self.gui.Visible = false
	end
end

function StatsUI:RequestExit()
	if self.onExitRequested then
		self.onExitRequested()
	end
end

function StatsUI:Destroy()
	if self.gui and self.gui.Parent then
		self.gui:Destroy()
	end
end

return StatsUI
