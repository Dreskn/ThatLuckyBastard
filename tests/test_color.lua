-- The accent colour of the Modern theme: teal unless the options choose
-- another (the player's class colour, or three values of their own), and
-- the Color section of the options that chooses it.
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end

RAID_CLASS_COLORS.SHAMAN = { r = 0, g = 0.44, b = 0.87 } -- the player of the tests is a shaman
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
local o = db.options

-- An option of the panel, by its label (a swatch's is its name).
local function control(label)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if rawget(w, "get") and (rawget(w, "label") == label or (type(t) == "table" and t.__text == label)) then
            return w
        end
    end
    error("no option labelled " .. label)
end
local function click(label)
    local b = control(label)
    b.__scripts.OnClick(b)
end
local function ticked(label) return control(label).get() and true or false end
local function greyed(label) return not control(label):IsEnabled() end
-- A colour as three figures, to compare and to print.
local function Is(c, r, g, b)
    return c ~= nil and math.abs(c[1] - r) < 0.002 and math.abs(c[2] - g) < 0.002 and math.abs(c[3] - b) < 0.002
end
local function Accent(r, g, b) return Is(ns.ACCENT, r, g, b) end
local function Shade() return ("%.2f %.2f %.2f"):format(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3]) end
-- What is painted in the accent: the line under every Modern title bar,
-- the cogwheel's wash, and the mark under a button (`label`) of a window
-- that may not even be open.
local function Lines(r, g, b)
    local n, right = 0, 0
    for _, w in ipairs(FRAMES) do
        local line = rawget(w, "accentLine")
        if line then
            n = n + 1
            if Is(line.__color, r, g, b) then right = right + 1 end
        end
    end
    return n > 3 and right == n, n
end
local function Cog()
    for _, w in ipairs(FRAMES) do
        if rawget(w, "cog") == true then return w.hl.__color end
    end
end
local function Mark(label)
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == label then return w.flat.mark.__color end
    end
end
-- The three sliders of the custom colour, and its swatch.
local sliders = {}
for _, w in ipairs(FRAMES) do
    if w.__kind == "Slider" and rawget(w, "channel") then sliders[w.channel] = w end
end
local function Slide(channel, value) sliders[channel].__scripts.OnValueChanged(sliders[channel], value) end
local TEAL = { 0.25, 0.78, 0.72 }

ns.ToggleOptions()
ns.ShowWindow()

print("-- to begin with")
check(o.accent == "teal" and Accent(unpack(TEAL)) and ns.Title("x"):find("|cff40c7b8Lucky", 1, true) ~= nil,
      "the accent is the addon's teal, and so is the middle word of every title")
local all, windows = Lines(unpack(TEAL))
check(all, ("the line under each of the %d Modern title bars is teal"):format(windows))
check(ticked("TLB") and not ticked("Custom") and not greyed("TLB"), "in the options, TLB is the colour chosen")
for _, label in ipairs({ "TLB", "Class", "Custom" }) do control(label) end
local gone = 0
for _, label in ipairs({ "Teal", "Amber", "Light", "Dark" }) do
    if not pcall(control, label) then gone = gone + 1 end
end
check(gone == 4, "Amber, Light and Dark are gone, and Teal is called TLB")
check(#sliders == 3 and sliders[1].label.__text == "R" and sliders[2].label.__text == "G" and sliders[3].label.__text == "B",
      "TLB, Class, and Custom with its three values: R, G and B")
check(sliders[1]:GetAlpha() == 0.4 and sliders[3]:GetAlpha() == 0.4, "which are greyed out while Custom is not the choice")

print("-- the class colour")
click("Class")
check(o.accent == "class" and Accent(0, 0.44, 0.87) and ticked("Class") and not ticked("TLB"),
      "Class: the player's class colour, a shaman's blue here (" .. Shade() .. ")")
check(ns.Title("x"):find("|cff0070deLucky", 1, true) ~= nil, "titles follow")
check(Lines(0, 0.44, 0.87), "so does the line under every title bar, open or not")
check(Is(Cog(), 0, 0.44, 0.87) and Is(Mark("Front page"), 0, 0.44, 0.87), "the cogwheel's wash and the mark under a button of the window")
check(Is(Mark("Dungeons"), 0, 0.44, 0.87), "and under a tab of the statistics, which are not open")
check(ns.BRAND:find("|cff40c7b8Lucky", 1, true) ~= nil and ns.TEAL_HEX == "|cff40c7b8",
      "in chat and on links the addon keeps its own teal")

print("-- a colour of one's own")
click("Custom")
check(o.accent == "custom" and Accent(unpack(TEAL)) and sliders[1]:GetAlpha() == 1,
      "Custom starts from the teal, and its three values are live")
Slide(1, 255)
check(o.accentCustom[1] == 1 and Accent(1, 0.78, 0.72), "red all the way up: " .. Shade())
Slide(2, 0)
Slide(3, 127.6)
check(Accent(1, 0, 128 / 255) and o.accentCustom[3] == 128 / 255, "green down and blue half way, to the nearest of 256 steps: " .. Shade())
check(ns.Title("x"):find("|cffff0080Lucky", 1, true) ~= nil and Lines(1, 0, 128 / 255) and Is(Cog(), 1, 0, 128 / 255),
      "and everything follows as the sliders move")
click("TLB")
Slide(1, 10)
check(o.accentCustom[1] == 10 / 255 and Accent(unpack(TEAL)) and sliders[1]:GetAlpha() == 0.4,
      "with another colour chosen, the values are kept for later and change nothing")
Slide(1, 255)
click("Custom")
check(Accent(1, 0, 128 / 255), "Custom brings them back")

print("-- the game's colour picker")
local picked
ColorPickerFrame = {
    SetupColorPickerAndShow = function(self, info) picked = info end,
    GetColorRGB = function() return 0.2, 0.4, 0.6 end,
}
click("Custom")
check(picked and picked.r == 1 and picked.g == 0 and picked.b == 128 / 255 and not picked.hasOpacity,
      "Custom also opens the game's colour picker, where the game has one, on the colour as it is")
picked.swatchFunc()
check(Accent(0.2, 0.4, 0.6) and o.accentCustom[2] == 0.4, "a colour picked there is taken as the custom colour")
picked.cancelFunc()
check(Accent(1, 0, 128 / 255), "cancelled, the colour is what it was")
local opened
ColorPickerFrame = {
    SetColorRGB = function(self, r, g, b) self.rgb = { r, g, b } end,
    GetColorRGB = function() return 0.5, 0.5, 0.5 end,
}
ShowUIPanel = function(f) opened = f end
click("Custom")
check(opened == ColorPickerFrame and ColorPickerFrame.rgb[1] == 1 and ColorPickerFrame.func ~= nil,
      "an older picker is opened the older way")
ColorPickerFrame.func()
check(Accent(0.5, 0.5, 0.5), "and works the same")
ColorPickerFrame.cancelFunc()
ColorPickerFrame, ShowUIPanel = nil, nil
check(Accent(1, 0, 128 / 255), "without one, the sliders do it alone")

print("-- the Modern theme's alone")
-- The cogwheel's look: its picture, its tint, and whether it sits on a key.
local function CogIs(folder, picture, tint, onKey)
    if onKey == nil then -- no folder: the game's own
        folder, picture, tint, onKey = "Interface", folder, picture, tint
    end
    for _, w in ipairs(FRAMES) do
        if rawget(w, "cog") == true then
            local icon, t = w.icon, w.icon.__tint or { 1, 1, 1 }
            local path = tostring(icon.__texture)
            return path:find(folder, 1, true) ~= nil and path:sub(-#picture) == picture and Is(t, unpack(tint))
                and w.face:IsShown() == onKey and w.edge:IsShown() == onKey
        end
    end
    return false
end
check(CogIs("ThatLuckyBastard", "gear.tga", { 1, 1, 1 }, false), "in Modern the cogwheel is our own flat gear, white")
click("Classic")
check(db.theme == "classic" and Accent(unpack(TEAL)) and o.accent == "custom", "in Classic the accent is the teal again; the choice is kept")
local greys = 0
for _, label in ipairs({ "TLB", "Class", "Custom" }) do
    if greyed(label) then greys = greys + 1 end
end
check(greys == 3 and sliders[2]:GetAlpha() == 0.4, "and the whole Color section is greyed out")
check(CogIs("INV_Misc_Gear_01", { 1, 1, 1 }, false), "Classic keeps the game's gear icon")
click("Receipt")
check(Accent(unpack(TEAL)) and greyed("Class"), "in Receipt too")
check(CogIs("ThatLuckyBastard", "gear.tga", { 0.165, 0.153, 0.141 }, true), "Receipt's is the flat gear in ink, on a till key")
click("Modern")
check(Accent(1, 0, 128 / 255) and not greyed("Class") and sliders[2]:GetAlpha() == 1, "back in Modern, it is the colour chosen again")
check(CogIs("ThatLuckyBastard", "gear.tga", { 1, 1, 1 }, false) and Is(Cog(), 1, 0, 128 / 255), "and the gear is white again, off its key, washed in the accent")
ns.ToggleOptions() -- with the options shut, nothing else applies it
SlashCmdList.THATLUCKYBASTARD("theme classic")
check(Accent(unpack(TEAL)) and not ThatLuckyBastardOptionsFrame:IsShown(), "/tlb theme changes it likewise, the options shut")
SlashCmdList.THATLUCKYBASTARD("theme modern")
check(Accent(1, 0, 128 / 255) and Lines(1, 0, 128 / 255), "both ways")
ns.ToggleOptions()

print("-- kept, and put back")
local saved = Reload()
db, o = saved, saved.options
check(o.accent == "custom" and Accent(1, 0, 128 / 255), "the colour is there again after logging out and back in")
for _, old in ipairs({ "amber", "light", "dark" }) do
    o.accent = old
    Fire("ADDON_LOADED", "ThatLuckyBastard")
    check(o.accent == "teal" and Accent(unpack(TEAL)), old .. ", saved before 0.7.1, is the teal again as the addon loads")
end
o.accent = "custom"
Fire("ADDON_LOADED", "ThatLuckyBastard")
check(o.accent == "custom" and Accent(1, 0, 128 / 255), "a colour still on offer is kept, and applied as the addon loads")
-- The class is not known that early: its colour comes at login.
o.accent = "class"
local realUnitClass = UnitClass
UnitClass = function() return nil end
Fire("ADDON_LOADED", "ThatLuckyBastard")
check(Accent(unpack(TEAL)), "a class not known yet leaves the teal")
UnitClass = realUnitClass
Fire("PLAYER_LOGIN")
check(Accent(0, 0.44, 0.87), "and its colour comes at login")
StaticPopupDialogs.THATLUCKYBASTARD_DEFAULTS.OnAccept()
check(o.accent == "teal" and Accent(unpack(TEAL)) and Is(o.accentCustom, unpack(TEAL)) and Lines(unpack(TEAL)),
      "Defaults puts the teal back, and the custom colour with it")

print("-- values that make no colour")
o.accent = "purple"
ns.ApplyAccent()
check(Accent(unpack(TEAL)), "a colour the addon does not know is the teal")
o.accent, o.accentCustom = "custom", { 5, -1, "x" }
ns.ApplyAccent()
check(Accent(1, 0, 0), "values out of range are brought into it, and what is no number counts as none (" .. Shade() .. ")")
o.accentCustom = "blue"
ns.ApplyAccent()
check(Accent(unpack(TEAL)), "and a custom colour that is no colour at all is the teal")
Fire("ADDON_LOADED", "ThatLuckyBastard")
check(type(o.accentCustom) == "table" and Is(o.accentCustom, unpack(TEAL)), "which loading puts right in the saved options")
o.accent = "teal"
ns.ApplyAccent()
ns.ToggleOptions()
ThatLuckyBastardFrame:Hide()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (color)")
