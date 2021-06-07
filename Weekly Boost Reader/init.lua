-------------------------------------------------------------------------------
-- Weekly Boost Reader: 
-- Displays weekly Ephinea boosts (see ephinea.pioneer2.net/kill-counters)
-------------------------------------------------------------------------------
local ADDON_NAME = "Weekly Boost Reader"
local ADDON_HOME = "addons/" .. ADDON_NAME .. "/"
local OPT_NAME = "options.lua"
local BOOST_URL = "https://ephinea.pioneer2.net/kill-counters"
local BOOST_SELECTOR = ".table-bordered strong"
local ACTIVE = 4
local NEXT = 6
local updated = false
local cfg_window
local activeBoost
local nextBoost

local core_mainmenu  = require("core_mainmenu")
local lib_helpers    = require("solylib.helpers")
local cfg            = require(ADDON_NAME .. ".configuration")
local request        = require(ADDON_NAME .. ".luajit-request")
local htmlparser     = require(ADDON_NAME .. ".htmlparser")
local dump           = require(ADDON_NAME .. ".dump")
local lib_theme_loaded, lib_theme = pcall(require, "Theme Editor.theme")
local options_loaded, options = pcall(require, ADDON_NAME .. ".options")

local OPT_DEFAULT =  {
	H = 80,
	W = 300,
	X = 0,
	Y = 0,
	anchor = 1,
	configurationWindowEnable = false,
	enable = true,
	activeBoost = true,
	nextBoost = true,
	noMove = "",
	noResize = "NoResize",
	noTitleBar = "NoTitleBar",
	transparentWindow = true,
}

local function SaveOptions()
    dump.tofile(options, ADDON_HOME .. OPT_NAME)
end

local function CheckOptions()
    if options_loaded then
        for k,v in pairs(OPT_DEFAULT) do
            -- If anything is nil, just copy over defaults
            options[k] = options[k] and opt or options[k]
        end
    else
        -- No options loaded, so load defaults and save file
        options = {}
        for k, v in pairs(OPT_DEFAULT) do
            options[k] = v
        end
        SaveOptions()
    end
end

local function GetBoostString(root, type)
    local boost = root(BOOST_SELECTOR)
    return boost[type]:getcontent() .. "%"
end

local function UpdateBoosts()
    local response = request.send(BOOST_URL)
    if response and response.code == 200 then
      local root = htmlparser.parse(response.body)
         if root then
          activeBoost = GetBoostString(root, ACTIVE)
          nextBoost = GetBoostString(root, NEXT)
         end
    end
end

local function ShowBoosts()
    if options.activeBoost then
        imgui.Text("Active: " .. activeBoost)
    end
    if options.nextBoost then
        imgui.Text("Next: " .. nextBoost)
    end
end

local function present()
    if options.configurationWindowEnable then
        cfg_window.open = true
        options.configurationWindowEnable = false
    end
    
    local cfg_window_changed= false
    cfg_window.Update()
    if cfg_window.changed then
        cfg_window_changed = true
        cfg_window.changed = false
        SaveOptions()
    end

    if options.enable == false then
        return
    end

    if options.transparentWindow == true then
        imgui.PushStyleColor("WindowBg", 0.0, 0.0, 0.0, 0.0)
    end

    imgui.Begin(ADDON_NAME, nil, {options.noMove, options.noResize, options.noTitleBar})

    if not updated  then
        UpdateBoosts()
        updated = true
    end

    ShowBoosts()
    lib_helpers.WindowPositionAndSize(ADDON_NAME, options.X, options.Y, options.W, options.H, options.anchor, "", cfg_window_changed)
    imgui.End()

    if options.transparentWindow == true then
        imgui.PopStyleColor()
    end
end

local function init()
    CheckOptions()
    cfg_window = cfg.ConfigurationWindow(options, ADDON_NAME)

    local function mainMenuButtonHandler()
        cfg_window.open = not cfg_window.open
    end

    core_mainmenu.add_button(ADDON_NAME, mainMenuButtonHandler)

    return 
    {
        name = 'Weekly Boost Reader',
        version = '0.1.0',
        author = 'moya',
        present = present,
        toggleable = true,
    }
end

return 
{
    __addon = 
    {
        init = init,
    },
}