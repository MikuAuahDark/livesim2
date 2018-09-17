-- Main game
-- Part of Live Simulator: 2
-- See copyright notice in main.lua

local love = require("love")
local color = require("color")
local async = require("async")
local assetCache = require("asset_cache")
local timer = require("libs.hump.timer")
local log = require("logging")
local setting = require("setting")
local util = require("util")

local audioManager = require("audio_manager")
local gamestate = require("gamestate")
local loadingInstance = require("loading_instance")

local tapSound = require("game.tap_sound")
local beatmapList = require("game.beatmap.list")
local backgroundLoader = require("game.background_loader")
local note = require("game.live.note")
local liveUI = require("game.live.ui")
local BGM = require("game.bgm")

local DEPLS = gamestate.create {
	fonts = {
		main = {"fonts/MTLmr3m.ttf", 12},
	},
	images = {
		note = {"noteImage:assets/image/tap_circle/notes.png", {mipmaps = true}},
		longNoteTrail = {"assets/image/ef_326_000.png"},
		dummyUnit = {"assets/image/dummy.png", {mipmaps = true}}
	},
	audios = {}
}

local function playTapSFXSound(tapSFX, name, nsAccumulation)
	local list = tapSFX[tapSFX[name]]
	if list.alreadyPlayed == false then
		-- first element should be the least played
		local audio
		if audioManager.isPlaying(list[1]) then
			-- ok no more space
			audio = audioManager.clone(tapSFX[name])
		else
			audio = table.remove(list, 1)
		end

		audioManager.play(audio)
		list[#list + 1] = audio

		if nsAccumulation then
			list.alreadyPlayed = true
		end
	end
end

function DEPLS:load(arg)
	-- sanity check
	assert(arg.summary, "summary data missing")
	assert(arg.beatmapName, "beatmap name id missing")

	-- load live UI
	self.data.liveUI = liveUI.newLiveUI("sif")
	-- Lane definition
	self.persist.lane = self.data.liveUI:getLanePosition()
	-- Create new note manager
	self.data.noteManager = note.newNoteManager({
		image = self.assets.images.note,
		trailImage = self.assets.images.longNoteTrail,
		noteSpawningPosition = self.data.liveUI:getNoteSpawnPosition(),
		lane = self.persist.lane,
		accuracy = {16, 40, 64, 112, 128},
		autoplay = true, -- Testing only
		callback = function(object, lane, position, judgement, releaseFlag)
			self.data.liveUI:comboJudgement(judgement, releaseFlag ~= 1)
			if releaseFlag ~= 1 then
				self.data.liveUI:addScore(math.random(256, 1024))
				self.data.liveUI:addTapEffect(position.x, position.y, 255, 255, 255, 1)
			end

			-- play SFX
			if judgement ~= "miss" then
				playTapSFXSound(self.data.tapSFX, judgement, self.data.tapNoteAccumulation)
			end
			if judgement ~= "perfect" and judgement ~= "great" and object.star then
				playTapSFXSound(self.data.tapSFX, "starExplode", false)
			end
		end,
	})

	-- Load notes data
	local isBeatmapInit = 0
	beatmapList.getNotes(arg.beatmapName, function(chan)
		local amount = chan:pop()
		log.debug("livesim2", "received notes data: "..amount.." notes")
		local fullScore = 0
		for _ = 1, amount do
			local t = {}
			while chan:peek() ~= chan do
				local k = chan:pop()
				t[k] = chan:pop()
			end

			-- pop separator
			chan:pop()
			fullScore = fullScore + t.effect > 10 and 370 or 739
			self.data.noteManager:addNote(t)
		end

		self.data.noteManager:initialize()
		-- Set score range (c,b,a,s order)
		self.data.liveUI:setScoreRange(
			math.floor(fullScore * 211/739 + 0.5),
			math.floor(fullScore * 528/739 + 0.5),
			math.floor(fullScore * 633/739 + 0.5),
			fullScore
		)
		isBeatmapInit = isBeatmapInit + 1
	end)
	-- need to wrap in coroutine because
	-- there's no async access in the callback
	beatmapList.getBackground(arg.beatmapName, coroutine.wrap(function(value)
		log.debug("livesim2", "received background data")
		local tval = type(value)
		if tval == "table" then
			local bitval
			local m, l, r, t, b
			-- main background
			m = love.graphics.newImage(table.remove(value, 2))
			bitval = math.floor(value[1] / 4)
			-- left & right
			if bitval % 2 > 0 then
				l = love.graphics.newImage(table.remove(value, 2))
				r = love.graphics.newImage(table.remove(value, 2))
			end
			bitval = math.floor(value[1] / 2)
			-- top & bottom
			if bitval % 2 > 0 then
				t = love.graphics.newImage(table.remove(value, 2))
				b = love.graphics.newImage(table.remove(value, 2))
			end
			-- TODO: video
			self.data.background = backgroundLoader.compose(m, l, r, t, b)
		elseif tval == "number" and value > 0 then
			self.data.background = backgroundLoader.load(value)
		end
		isBeatmapInit = isBeatmapInit + 1
	end))
	-- Load unit data too
	beatmapList.getCustomUnit(arg.beatmapName, function(unitData)
		self.data.customUnit = unitData
		log.debug("livesim2", "received unit data")
		isBeatmapInit = isBeatmapInit + 1
	end)

	-- load tap SFX
	self.data.tapSFX = {accumulateTracking = {}}
	local tapSoundIndex = assert(tapSound[tonumber(setting.get("TAP_SOUND"))], "invalid tap sound")
	for k, v in pairs(tapSoundIndex) do
		if type(v) == "string" then
			local audio = audioManager.newAudio(v)
			audioManager.setVolume(audio, tapSoundIndex.volumeMultipler)
			self.data.tapSFX[k] = audio
			local list = {
				alreadyPlayed = false, -- for note sound accumulation
				audioManager.clone(audio)
			} -- cloned things
			self.data.tapSFX[audio] = list
			self.data.tapSFX.accumulateTracking[#self.data.tapSFX.accumulateTracking + 1] = list
		end
	end
	self.data.tapNoteAccumulation = assert(tonumber(setting.get("NS_ACCUMULATION")), "invalid note sound accumulation")

	-- wait until notes are loaded
	while isBeatmapInit < 3 do
		async.wait()
	end
	log.debug("livesim2", "beatmap init wait done")

	-- if there's no background, load default
	if not(self.data.background) then
		self.data.background = backgroundLoader.load(assert(tonumber(setting.get("BACKGROUND_IMAGE"))))
	end

	-- Try to load audio
	if arg.summary.audio then
		self.data.song = BGM.newSong(arg.summary.audio)
	end

	-- Set score range when available
	if arg.summary.scoreS then -- only check one
		self.data.liveUI:setScoreRange(
			arg.summary.scoreC,
			arg.summary.scoreB,
			arg.summary.scoreA,
			arg.summary.scoreS
		)
	end

	-- Initialize unit icons
	self.data.unitIcons = {}
	local unitDefaultName = {}
	local unitImageCache = {}
	local idolName = setting.get("IDOL_IMAGE")
	log.debug("livesim2", "default idol name: "..string.gsub(idolName, "\t", "\\t"))
	for w in string.gmatch(idolName, "[^\t]+") do
		unitDefaultName[#unitDefaultName + 1] = w
	end
	assert(#unitDefaultName == 9, "IDOL_IMAGE setting is not valid")
	log.debug("livesim2", "initializing units")
	for i = 1, 9 do
		local image

		if self.data.customUnit[i] then
			image = unitImageCache[self.data.customUnit[i]]
			if not(image) then
				image = love.graphics.newImage(self.data.customUnit[i], {mipmaps = true})
				unitImageCache[self.data.customUnit[i]] = image
			end
		else
			-- Default unit name are in left to right order
			-- but SIF units are in right to left order
			image = unitImageCache[unitDefaultName[10 - i]]
			if not(image) then
				if unitDefaultName[10 - i] == " " then
					image = self.assets.images.dummyUnit
				else
					local file = "unit_icon/"..unitDefaultName[10 - i]
					if util.fileExists(file) then
						image = assetCache.loadImage("unit_icon/"..unitDefaultName[10 - i])
					else
						image = self.assets.images.dummyUnit
					end
				end

				unitImageCache[unitDefaultName[10 - i]] = image
			end
		end

		self.data.unitIcons[i] = image
	end

	log.debug("livesim2", "ready")
end

function DEPLS:start()
	self.persist.debugTimer = timer.every(1, function()
		-- note debug
		log.debug("livesim2", "note remaining "..#self.data.noteManager.notesList)
		-- song debug
		if self.data.song then
			local audiotime = self.data.song:tell() * 1000
			local notetime = self.data.noteManager.elapsedTime * 1000
			log.debug("livesim2", string.format("audiotime: %.2fms, notetime: %.2fms, diff: %.2fms", audiotime, notetime, math.abs(audiotime - notetime)))
		end
	end)
	if self.data.song then
		self.data.song:play()
	end
end

function DEPLS:exit()
	timer.cancel(self.persist.debugTimer)
	if self.data.song then
		self.data.song:pause()
	end
end

function DEPLS:update(dt)
	for i = 1, #self.data.tapSFX.accumulateTracking do
		self.data.tapSFX.accumulateTracking[i].alreadyPlayed = false
	end

	self.data.noteManager:update(dt)
	self.data.liveUI:update(dt)
end

function DEPLS:draw()
	-- draw background
	love.graphics.setColor(color.compat(255, 255, 255, 0.25))
	love.graphics.draw(self.data.background)
	self.data.liveUI:drawHeader()
	love.graphics.setColor(color.white)
	for i, v in ipairs(self.persist.lane) do
		love.graphics.draw(self.data.unitIcons[i], v.x, v.y, 0, 1, 1, 64, 64)
	end

	self.data.noteManager:draw()
	self.data.liveUI:drawStatus()
end

DEPLS:registerEvent("keyreleased", function(_, key)
	if key == "escape" then
		return gamestate.leave(loadingInstance.getInstance())
	end
end)

return DEPLS