--[[
  Docent-Proof MPV - mpv script
  ---------------------------------------------------------------
  Slide 1: full-screen image (the "logo"), shown until NEXT is pressed.
  Slide 2: the featured video. When it ends, the image comes back.

  Folders (re-read every time, so web-panel changes apply instantly):
    <base_dir>\                     images; the chosen one is named in logo.txt
    <base_dir>\dp-videos\featured\  the one video that plays

  Clicker keys (most Bluetooth presenters send PageDown/PageUp or arrows):
    NEXT : PageDown, Right, Down, Space, Enter, left mouse click
    BACK : PageUp, Left, Up        (stops a playing video -> back to image)
    Ctrl+I : show the config-panel address on screen for 15 s
    Ctrl+M : minimize (to use other programs)   Ctrl+K : clicker key test
    Ctrl+Q : quit the player (staff only)
]]

local mp      = require 'mp'
local utils   = require 'mp.utils'
local msg     = require 'mp.msg'
local options = require 'mp.options'

local o = {
    base_dir   = "",   -- passed in by start-docent.bat; fallback below
    next_keys  = "PGDWN,RIGHT,DOWN,SPACE,ENTER,KP_ENTER,MBTN_LEFT",
    back_keys  = "PGUP,LEFT,UP",
    poll_seconds = 3,  -- how often to check for a new logo while idle
}
options.read_options(o, "docent")

local BASE = o.base_dir
if BASE == "" then
    local home = os.getenv("USERPROFILE") or os.getenv("HOME") or "."
    BASE = utils.join_path(utils.join_path(home, "Videos"), "docent-proof")
end
local VIDEOS   = utils.join_path(BASE, "dp-videos")
local FEATURED = utils.join_path(VIDEOS, "featured")
local LOGO_TXT = utils.join_path(BASE, "logo.txt")
local ADDR_TXT = utils.join_path(BASE, "config-address.txt")

local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
local IMAGE_EXT = set{"jpg","jpeg","png","bmp","gif","webp","tif","tiff"}
local VIDEO_EXT = set{"mp4","m4v","mov","mkv","webm","avi","wmv","mpg","mpeg","ts"}

local function ext(name) return (name:match("%.([^%.\\/]+)$") or ""):lower() end

local function list_files(dir, exts)
    local out = {}
    for _, f in ipairs(utils.readdir(dir, "files") or {}) do
        if exts[ext(f)] then out[#out + 1] = f end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

local function read_first_line(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*l"); f:close()
    if not s then return nil end
    s = s:gsub("^\239\187\191", "")          -- strip UTF-8 BOM
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The chosen image (logo.txt), or the first image alphabetically.
local function pick_image()
    local imgs = list_files(BASE, IMAGE_EXT)
    local want = read_first_line(LOGO_TXT)
    if want and want ~= "" then
        for _, f in ipairs(imgs) do
            if f == want then return utils.join_path(BASE, f) end
        end
    end
    return imgs[1] and utils.join_path(BASE, imgs[1]) or nil
end

local function pick_video()
    local v = list_files(FEATURED, VIDEO_EXT)
    return v[1] and utils.join_path(FEATURED, v[1]) or nil
end

------------------------------------------------------------------
local mode          = "image"   -- "image" | "video"
local current_image = nil
local current_video = nil

local function show_image()
    mode = "image"
    current_video = nil
    current_image = pick_image()
    if current_image then
        mp.commandv("loadfile", current_image, "replace")
    else
        mp.commandv("stop")
        mp.osd_message("No image found in:\n" .. BASE, 10)
    end
end

local function play_video()
    local v = pick_video()
    if not v then
        mp.osd_message("No featured video is set.", 4)
        return
    end
    mode = "video"
    current_video = v
    -- Queue the image right behind the video so mpv cuts straight back to it
    -- when the video ends (no black gap).
    mp.commandv("loadfile", v, "replace")
    current_image = pick_image()
    if current_image then mp.commandv("loadfile", current_image, "append") end
end

local function on_next()
    if mode == "image" then play_video() end
    -- During a video NEXT is ignored, so a double-click can't restart it.
end

local function on_back()
    if mode == "video" then show_image() end
end

-- Keep `mode` in sync with what mpv is actually showing.
-- In video mode the playlist is always [video, image], so position 0 = video.
-- (Uses the playlist position, not the file path: on Windows mpv may report
-- the path with different slashes than we passed in, which broke BACK.)
mp.register_event("file-loaded", function()
    if current_video and mp.get_property_number("playlist-pos", -1) == 0 then
        mode = "video"
    else
        mode = "image"
        current_video = nil
    end
end)

-- Safety net: if the player ever goes idle during a video (e.g. no image
-- was queued), put the image back up.
mp.observe_property("idle-active", "bool", function(_, idle)
    if idle and mode == "video" then show_image() end
end)

-- While idle on the image, pick up a new logo chosen in the web panel.
mp.add_periodic_timer(o.poll_seconds, function()
    if mode == "image" and pick_image() ~= current_image then show_image() end
end)

------------------------------------------------------------------
local function bind_keys(csv, name, fn)
    local i = 0
    for k in csv:gmatch("[^,%s]+") do
        i = i + 1
        mp.add_forced_key_binding(k, name .. i, fn)
    end
end
bind_keys(o.next_keys, "docent-next-", on_next)
bind_keys(o.back_keys, "docent-back-", on_back)

mp.add_forced_key_binding("ctrl+i", "docent-info", function()
    local f = io.open(ADDR_TXT, "rb")
    local txt = f and f:read("*a") or "Config address not found (is the config server running?)"
    if f then f:close() end
    mp.osd_message("Docent-Proof MPV settings page:\n" .. txt, 15)
end)
mp.add_forced_key_binding("ctrl+q", "docent-quit", function() mp.command("quit 0") end)

-- Ctrl+M: minimize the player so staff can use other programs.
-- Click the player on the taskbar (or Alt+Tab) to bring it back.
mp.add_forced_key_binding("ctrl+m", "docent-minimize", function()
    mp.set_property_bool("window-minimized", true)
end)

-- Ctrl+K: key test. For 20 s, every key/button press shows its name on screen
-- instead of doing anything - use it to see what a clicker actually sends.
mp.add_forced_key_binding("ctrl+k", "docent-keytest", function()
    mp.set_property_bool("input-test", true)
    mp.osd_message("KEY TEST for 20 seconds: press clicker buttons...", 3)
    mp.add_timeout(20, function()
        mp.set_property_bool("input-test", false)
        mp.osd_message("Key test finished.", 2)
    end)
end)

msg.info("Docent-Proof MPV using folder: " .. BASE)
show_image()
