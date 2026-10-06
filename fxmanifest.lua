fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'codera-hud'
author 'Codera'
description 'Codera HUD '
version '2.0.0'

ui_page 'html/index.html'

shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'bridge/adapter.lua',
    'client/display.lua',
    'client/preferences.lua',
    'client/chatbox.lua',
    'client/hud.lua',
    'client/radar.lua',
}

server_scripts {
    'server/core.lua',
    'server/chatbox.lua',
}

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/img/*.png',
    'html/fonts/*.ttf',
    'html/fonts/*.txt',
    'stream/*.*',
}
