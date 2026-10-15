

-- Display Settings (nwg-displays): open as a centered floating window big enough to show the Apply button
hl.window_rule({match = {class = "^(nwg-displays)$"}, float = true})
hl.window_rule({match = {class = "^(nwg-displays)$"}, center = true})
hl.window_rule({match = {class = "^(nwg-displays)$"}, size = {"(monitor_w*0.70)", "(monitor_h*0.75)"} })

-- Display Settings (custom/display-switcher/settings.qml): centered floating window
hl.window_rule({match = {title = "^(Display Settings)$"}, float = true})
hl.window_rule({match = {title = "^(Display Settings)$"}, center = true})
hl.window_rule({match = {title = "^(Display Settings)$"}, size = {900, 880}})
