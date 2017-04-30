-- Aquashine base initializer & utilities function
-- Part of DEPLS2
-- Copyright � 2038 Dark Energy Processor

local ASArg = ...	-- Must contain entry point lists
local AquaShine = {
	CurrentEntryPoint = nil,
	LogicalScale = {
		ScreenX = ASArg.Width or 960,
		ScreenY = ASArg.Height or 640,
		OffX = 0,
		OffY = 0,
		ScaleOverall = 1
	},
}

local love = require("love")
local JSON = require("JSON")
local Yohane = require("Yohane")
local Shelsha = require("Shelsha")
local SkipCall = 0

----------------------------------
-- AquaShine Utilities Function --
----------------------------------

--! @brief Calculates touch position to take letterboxing into account
--! @param x Uncalculated X position
--! @param y Uncalculated Y position
--! @returns Calculated X and Y positions (2 values)
function AquaShine.CalculateTouchPosition(x, y)
	return
		(x - AquaShine.LogicalScale.OffX) / AquaShine.LogicalScale.ScaleOverall,
		(y - AquaShine.LogicalScale.OffY) / AquaShine.LogicalScale.ScaleOverall
end

local mount_target
--! @brief Mount a zip file, relative to DEPLS save directory.
--!        Unmounts previous mounted zip file, so only one zip file
--!        can be mounted.
--! @param path The Zip file path (or nil to clear)
--! @param target The Zip mount point
--! @returns Previous mounted ZIP filename (or nil if no Zip was mounted)
function AquaShine.MountZip(path, target)
	local prev_mount = mount_target
	
	if path ~= nil and mount_target == path then
		return prev_mount
	end
	
	if mount_target then
		love.filesystem.unmount(mount_target)
		mount_target = nil
	end
	
	if path then
		assert(love.filesystem.mount(path, target))
		
		mount_target = path
	end
	
	return prev_mount
end

local config_list = {}
--! @brief Parses configuration passed from command line
--!        Configuration passed via "/<key>[=<value=true>]" <key> is case-insensitive.
--!        If multiple <key> is found, only the first one takes effect.
--! @param argv Argument vector
--! @note This function modifies the `argv` table
function AquaShine.ParseCommandLineConfig(argv)
	if love.filesystem.isFused() == false then
		table.remove(argv, 1)
	end
	
	local arglen = #arg
	
	for i = arglen, 1, -1 do
		local k, v = arg[i]:match("/(%w+)=?(.*)")
		
		if k and v then
			config_list[k:lower()] = #v == 0 and true or tonumber(v) or v
			table.remove(arg, i)
		end
	end
end

--! @brief Get configuration argument passed from command line
--! @param key The configuration key (case-insensitive)
--! @returns The configuration value or `nil` if it's not set
function AquaShine.GetCommandLineConfig(key)
	return config_list[key:lower()]
end

--! @brief Set configuration
--! @param key The configuration name (case-insensitive)
--! @param val The configuration value
function AquaShine.SaveConfig(key, val)
	local file = assert(love.filesystem.newFile(key:upper()..".txt", "w"))
	
	file:write(tostring(default_value))
	file:close()
end

--! @brief Get configuration
--! @param key The configuration name (case-insensitive)
--! @param defval The configuration default value
function AquaShine.LoadConfig(key, defval)
	local file = love.filesystem.newFile(key:upper()..".txt")
	
	if not(file:open("r")) then
		assert(file:open("w"))
		file:write(tostring(defval))
		file:close()
		
		return defval
	end
	
	local data = file:read()
	
	return tonumber(data) or data
end

--! @brief Loads entry point
--! @param name The entry point Lua script file
--! @param arg Additional argument to be passed
function AquaShine.LoadEntryPoint(name, arg)
	local scriptdata = assert(love.filesystem.load(name))()
	scriptdata.Start(arg or {})
	AquaShine.CurrentEntryPoint = scriptdata
	
	SkipCall = 1
end

--! Function used to replace extension on file
local function substitute_extension(file, ext_without_dot)
	return file:sub(1, ((file:find("%.[^%.]*$")) or #file+1)-1).."."..ext_without_dot
end
--! @brief Load audio
--! @param path The audio path
--! @param noorder Force existing extension?
--! @returns Audio handle or `nil` plus error message on failure
function AquaShine.LoadAudio(path, noorder)
	local _, token_image
	
	if not(noorder) then
		local a = AquaShine.LoadAudio(substitute_extension(path, "wav"), true)
		
		if a == nil then
			a = AquaShine.LoadAudio(substitute_extension(path, "ogg"), true)
			
			if a == nil then
				return AquaShine.LoadAudio(substitute_extension(path, "mp3"), true)
			end
		end
		
		return a
	end
	
	-- Try save dir
	do
		local file = love.filesystem.newFile(path)
		
		if file:open("r") then
			_, token_image = pcall(love.sound.newSoundData, file)
			
			if _ then
				return token_image
			end
		end
	end
	
	_, token_image = pcall(love.sound.newSoundData, path)
	
	if _ == false then return nil, token_image
	else return token_image end
end
----------------------------
-- AquaShine Font Caching --
----------------------------
local FontList = {}

--! @brief Load font
--! @param name The font name
--! @param size The font size
--! @returns Font object or nil on failure
function AquaShine.LoadFont(name, size)
	if not(FontList[name]) then
		FontList[name] = {}
	end
	
	if not(FontList[name][size]) then
		local _, a = pcall(love.graphics.newFont, name, size)
		
		if _ then
			FontList[name][size] = a
		else
			return nil, a
		end
	end
	
	return FontList[name][size]
end

--------------------------------------
-- AquaShine Image Loader & Caching --
--------------------------------------
local LoadedShelshaObject = {}
local LoadedImage = {}

--! @brief Load image without caching
--! @param path The image path
--! @param pngonly Do not load .png.imag file even if one exist
--! @returns Drawable object
--! @note The ShelshaObject texture bank will ALWAYS BE CACHED!.
function AquaShine.LoadImageNoCache(path, pngonly)
	assert(path:sub(-4) == ".png", "Only PNG image is supported")
	local _, img = pcall(love.graphics.newImage, path)
	
	if _ then
		-- .png image loaded
		return img
	elseif not(pngonly) then
		-- Try .png.imag
		local imag = love.filesystem.newFile(path .. ".imag", "r")
		
		if imag and imag:read(4) == "LINK" then
			local l = {imag:read(4):byte(1, 4)}
			local texbfile = imag:read(l[1] * 16777216 + l[2] * 65536 + l[3] * 256 + l[4]):gsub("%z", "")
			local shelsha_object = LoadedShelshaObject[texbfile]
			
			-- If TEXB not cached, load it and cache it
			if not(shelsha_object) then
				shelsha_object = Shelsha.newTextureBank(texbfile)
				LoadedShelshaObject[texbfile] = shelsha_object
			end
			
			return shelsha_object:getImageMesh(path:sub(1, -5))
		end
	else
		assert(false, string.format("Cannot load image %q", path))
	end
end

--! @brief Load image with caching
--! @param path The image path
--! @returns Drawable object
function AquaShine.LoadImage(path)
	local img = LoadedImage[path]
	
	if not(img) then
		img = AquaShine.LoadImageNoCache(path)
		LoadedImage[path] = img
	end
	
	return img
end

----------------------------------------------
-- AquaShine Scissor to handle letterboxing --
----------------------------------------------
function AquaShine.SetScissor(x, y, width, height)
	x, y = AquaShine.CalculateTouchPosition(x, y)
	
	love.graphics.setScissor(
		AquaShine.LogicalScale.OffX, AquaShine.LogicalScale.OffY,
		width * AquaShine.LogicalScale.ScaleOverall,
		height * AquaShine.LogicalScale.ScaleOverall
	)
end

function AquaShine.ClearScissor()
	love.graphics.setScissor()
end

------------------------------------
-- AquaShine love.* override code --
------------------------------------
function love.run()
	local dt = 0
	local font = AquaShine.LoadFont("MTLmr3m.ttf", 14)
	
	if love.math then
		love.math.setRandomSeed(os.time())
		math.randomseed(os.time())
	end
 
	love.load(arg)
	
	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then love.timer.step() end
 
	-- Main loop time.
	while true do
		-- Process events.
		if love.event then
			love.event.pump()
			for name, a,b,c,d,e,f in love.event.poll() do
				if name == "quit" then
					if love.quit then love.quit() end
					return a
				end
				
				love.handlers[name](a,b,c,d,e,f)
			end
		end
 
		-- Update dt, as we'll be passing it to update
		if love.timer then
			love.timer.step()
			dt = love.timer.getDelta()
		end
		
		if love.graphics and love.graphics.isActive() then
			love.graphics.clear(0, 0, 0)
			
			if AquaShine.CurrentEntryPoint then
				if SkipCall == 0 then
					dt = dt * 1000
					AquaShine.CurrentEntryPoint.Update(dt)
					love.graphics.push()
					
					love.graphics.translate(AquaShine.LogicalScale.OffX, AquaShine.LogicalScale.OffY)
					love.graphics.scale(AquaShine.LogicalScale.ScaleOverall)
					AquaShine.CurrentEntryPoint.Draw(dt)
					love.graphics.pop()
				else
					SkipCall = SkipCall - 1
				end
			else
				love.graphics.setFont(font)
				love.graphics.print("AquaShine loader: No entry point specificed/entry point rejected", 10, 10)
			end
			love.graphics.present()
		end
	end
end

-- Inputs
function love.mousepressed(x, y, button, istouch)
	if istouch == true then return end
	
	if AquaShine.CurrentEntryPoint.MousePressed then
		x, y = AquaShine.CalculateTouchPosition(x, y)
		AquaShine.CurrentEntryPoint.MousePressed(x, y, button, istouch)
	end
end

function love.mousemoved(x, y, dx, dy, istouch)
	if istouch == true then return end
	
	if AquaShine.CurrentEntryPoint.MouseMoved then
		x, y = AquaShine.CalculateTouchPosition(x, y)
		AquaShine.CurrentEntryPoint.MouseMoved(x, y, dx, dy, istouch)
	end
end

function love.mousereleased(x, y, button, istouch)
	if istouch == true then return end
	
	if AquaShine.CurrentEntryPoint.MouseReleased then
		x, y = AquaShine.CalculateTouchPosition(x, y)
		AquaShine.CurrentEntryPoint.MouseReleased(x, y, button, istouch)
	end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
	return love.mousepressed(x, y, 1, id)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
	return love.mousereleased(x, y, 1, id)
end

function love.touchmoved(id, x, y, dx, dy)
	return love.mousemoved(x, y, dx, dy, id)
end

function love.keypressed(key, scancode, repeat_bit)
	if AquaShine.CurrentEntryPoint.KeyPressed then
		AquaShine.CurrentEntryPoint.KeyPressed(key, scancode, repeat_bit)
	end
end

function love.keyreleased(key, scancode)
	if AquaShine.CurrentEntryPoint.KeyReleased then
		AquaShine.CurrentEntryPoint.KeyReleased(key, scancode)
	end
end

-- On thread error
function love.threaderror(t, msg)
	assert(false, msg)
end

-- Letterboxing recalculation
function love.resize(w, h)
	local lx, ly = ASArg.Width or 960, ASArg.Height or 640
	AquaShine.LogicalScale.ScreenX, AquaShine.LogicalScale.ScreenY = w, h
	AquaShine.LogicalScale.ScaleOverall = math.min(AquaShine.LogicalScale.ScreenX / lx, AquaShine.LogicalScale.ScreenY / ly)
	AquaShine.LogicalScale.OffX = (AquaShine.LogicalScale.ScreenX - AquaShine.LogicalScale.ScaleOverall * lx) / 2
	AquaShine.LogicalScale.OffY = (AquaShine.LogicalScale.ScreenY - AquaShine.LogicalScale.ScaleOverall * ly) / 2
end

-- When running low memory
local cache_list = {FontList, LoadedShelshaObject, LoadedImage}
function love.lowmemory()
	-- Remove all caches
	for i = 1, #cache_list do
		for n, v in pairs(cache_list[i]) do
			cache_list[i][n] = nil
		end
	end
	
	collectgarbage("collect")
end

-- Initialization
function love.load(arg)
	-- Initialization
	local wx, wy = love.graphics.getDimensions()
	AquaShine.ParseCommandLineConfig(arg)
	
	-- Flags check
	do
		local force_setmode = false
		local setmode_param = {
			fullscreen = false,
			fullscreentype = "desktop",
			resizable = true
		}
		
		if config_list.width then
			force_setmode = true
			wx = config_list.width
		end
		
		if config_list.height then
			force_setmode = true
			wy = config_list.height
		end
		
		if config_list.fullscreen then
			force_setmode = true
			setmode_param.fullscreen = true
			wx, wy = 0, 0
		end
		
		if force_setmode then
			love.window.setMode(wx, wy, setmode_param)
			
			if setmode_param.fullscreen then
				wx, wy = love.graphics.getDimensions()
			end
		end
	end
	
	love.resize(wx, wy)
	
	-- Load entry point
	if arg[1] and ASArg.Entries[arg[1]] and #arg > ASArg.Entries[arg[1]][1] then
		local entry = table.remove(arg, 1)
		
		AquaShine.LoadEntryPoint(ASArg.Entries[entry][2], arg)
		SkipCall = 0
	elseif ASArg.DefaultEntry then
		AquaShine.LoadEntryPoint(ASArg.Entries[ASArg.DefaultEntry][2], arg)
		SkipCall = 0
	end
end

return AquaShine
