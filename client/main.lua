local socket = require("socket")

-- =========================================================
-- 0. CONFIGURAÇÃO DE SISTEMA (LINUX)
-- =========================================================
-- Desativa o sinal de interrupção (Ctrl+C) para evitar saídas bruscas.
-- O terminal não vai mais matar o processo com Ctrl+C.
os.execute("stty -isig")

-- WRAPPER DO STDIN (A CORREÇÃO DO ERRO)
-- O LuaSocket precisa de um objeto com método getfd(), não apenas um número.
local stdin_mock = {
    getfd = function() return 0 end, -- 0 é o ID do teclado (stdin)
    dirty = function() return false end
}

-- Função para sair com elegância, avisar o servidor e restaurar o terminal
local function encerrar_sessao(sock)
    local c = { accent = "\27[38;2;203;166;247m", reset = "\27[0m" }

    -- 1. Tenta avisar o servidor (Modo Bloqueante rápido)
    if sock then
        sock:settimeout(nil) -- Bloqueia para garantir envio
        -- Usa pcall para não travar se o socket já estiver fechado
        pcall(function() sock:send("exit\n") end)
        sock:close()
    end

    -- 2. Restaura o Ctrl+C para o terminal voltar ao normal (MUITO IMPORTANTE)
    os.execute("stty isig")

    -- 3. Limpa e sai
    io.write("\27[2J\27[H")
    print(c.accent .. ">>> Sessão Deepconn Encerrada. Terminal restaurado." .. c.reset)
    os.exit()
end

-- =========================================================
-- 1. CONFIGURAÇÃO VISUAL (Catppuccin Mocha)
-- =========================================================
local c = {
    bg      = "\27[48;2;30;30;46m",
    fg      = "\27[38;2;205;214;244m",
    border  = "\27[38;2;88;91;112m",
    accent  = "\27[38;2;203;166;247m",
    user    = "\27[38;2;137;180;250m",
    msg_in  = "\27[38;2;166;227;161m",
    msg_out = "\27[38;2;249;226;175m",
    err     = "\27[38;2;243;139;168m",
    dim     = "\27[38;2;147;153;178m",
    reset   = "\27[0m"
}

local box = { h = "─", v = "│", tl = "┌", tr = "┐", bl = "└", br = "┘", t_down = "┬", t_up = "┴" }

local function clear() io.write("\27[2J\27[H") end
local function move(x, y) io.write(string.format("\27[%d;%dH", y, x)) end

-- =========================================================
-- 2. NOTIFICAÇÕES
-- =========================================================
local function escape_shell(texto)
    return string.format("%q", texto)
end

local function enviar_notificacao(usuario, mensagem)
    local cmd = string.format(
        "notify-send -a Deepconn -u normal %s %s",
        escape_shell("Mensagem de " .. usuario),
        escape_shell(mensagem)
    )
    os.execute(cmd .. " &")
end

-- =========================================================
-- 3. LOGIN
-- =========================================================
clear()
print(c.accent .. ">>> DEEPCONN SECURE SHELL v1.5 (Stable)" .. c.reset)
io.write(c.user .. "Username: " .. c.reset)
local username = io.read()

-- Se der erro na leitura (ex: Ctrl+D), sai
if not username then
    os.execute("stty isig")
    os.exit()
end

io.write(c.user .. "IP (Enter=localhost): " .. c.reset)
local ip = io.read()
if ip == "" then ip = "localhost" end

io.write(c.user .. "Porta (Enter=8080): " .. c.reset)
local porta = io.read()
if porta == "" then porta = 8080 end

local client = socket.tcp()
client:settimeout(5)
local res, err = client:connect(ip, porta)

if not res then
    print(c.err .. "Erro ao conectar: " .. err .. c.reset)
    os.execute("stty isig")
    os.exit(1)
end

client:send(username .. "\n")
client:settimeout(0) -- Modo não-bloqueante ativado

-- =========================================================
-- 4. ESTADO & UI
-- =========================================================
local state = {
    users = {},
    messages = {},
    target = nil,
    input = "",
    system_msg = "Bem-vindo. Use /u <nome> para iniciar chat."
}

local WIDTH, HEIGHT, SIDEBAR_W = 80, 24, 20
local CHAT_W = WIDTH - SIDEBAR_W - 3

local function draw_ui()
    clear()
    -- Header
    move(1, 1)
    local title = " DCNN "
    local header = string.rep(box.h, 2) .. c.accent .. title .. c.border .. string.rep(box.h, WIDTH - 4 - #title)
    io.write(c.border .. box.tl .. header:sub(1, WIDTH + #c.accent) .. box.tr .. c.reset)

    -- Corpo (Colunas)
    for y = 2, HEIGHT - 1 do
        move(1, y)
        io.write(c.border .. box.v .. string.rep(" ", SIDEBAR_W) .. box.v .. string.rep(" ", CHAT_W) .. box.v .. c.reset)
    end

    -- Rodapé
    move(1, HEIGHT)
    local bot = string.rep(box.h, SIDEBAR_W) .. box.t_up .. string.rep(box.h, CHAT_W)
    io.write(c.border .. box.bl .. bot .. box.br .. c.reset)

    -- Lista de Usuários
    move(2, 2)
    io.write(c.dim .. "NODES" .. c.reset)
    for i, u in ipairs(state.users) do
        if i + 2 >= HEIGHT then break end
        move(2, i + 2)
        if u == state.target then
            io.write(c.accent .. "> " .. u:sub(1, SIDEBAR_W - 2) .. c.reset)
        else
            io.write(c.user .. "  " .. u:sub(1, SIDEBAR_W - 2) .. c.reset)
        end
    end

    -- Cabeçalho do Chat
    move(SIDEBAR_W + 3, 2)
    if state.target then
        io.write(c.accent .. "@" .. state.target .. c.reset)
    else
        io.write(c.err .. "No Channel" .. c.reset)
    end

    move(SIDEBAR_W + 3, 3)
    io.write(c.dim .. state.system_msg:sub(1, CHAT_W) .. c.reset)

    -- Mensagens
    local max = HEIGHT - 5
    local start = math.max(1, #state.messages - max + 1)
    local cy = 4
    for i = start, #state.messages do
        local m = state.messages[i]
        local show = (m.target == "GLOBAL") or (m.sender == state.target) or
        (m.sender == "Eu" and m.target == state.target)
        if show then
            move(SIDEBAR_W + 3, cy)
            local txt = m.text:sub(1, CHAT_W - 2)
            if m.sender == "Eu" then
                io.write(c.msg_out .. "< Me: " .. c.fg .. txt .. c.reset)
            else
                io.write(c.msg_in .. "> " .. m.sender .. ": " .. c.fg .. txt .. c.reset)
            end
            cy = cy + 1
        end
    end

    -- Barra de Input
    move(1, HEIGHT + 1)
    io.write(c.accent .. "CMD > " .. c.reset .. state.input)
    io.flush()
end

-- =========================================================
-- 5. LOOP PRINCIPAL
-- =========================================================
draw_ui()

while true do
    -- AQUI ESTÁ A MÁGICA: Usamos stdin_mock em vez de 0
    local ler = { client, stdin_mock }
    local ready = socket.select(ler, nil, 0.05)
    local update = false

    for _, s in ipairs(ready) do
        -- EVENTO DE REDE
        if s == client then
            local line, err = client:receive()
            if not err then
                if line:match("^LISTA") then
                    local l = line:match("^LISTA (.+)")
                    state.users = {}
                    if l then for u in l:gmatch("([^,]+)") do if u ~= username then table.insert(state.users, u) end end end
                    update = true
                elseif line:match("^MSG") then
                    local rem, txt = line:match("^MSG ([^ ]+) (.+)")
                    if rem then
                        table.insert(state.messages, { sender = rem, text = txt, target = "Eu" })
                        if not state.target then state.target = rem end
                        enviar_notificacao(rem, txt)
                        update = true
                    end
                end
            else
                -- Servidor caiu ou erro de conexão
                encerrar_sessao(client)
            end

            -- EVENTO DE TECLADO (Comparando com o objeto Mock)
        elseif s == stdin_mock then
            local texto = io.read()
            if texto then
                if texto:sub(1, 1) == "/" then
                    if texto:match("^/u ") then
                        state.target = texto:sub(4)
                        state.system_msg = "Canal: " .. state.target
                    elseif texto == "/q" or texto == "/quit" then
                        encerrar_sessao(client)
                    end
                else
                    if state.target then
                        client:send("MSG " .. state.target .. " " .. texto .. "\n")
                        table.insert(state.messages, { sender = "Eu", text = texto, target = state.target })
                    else
                        state.system_msg = "ERRO: Use /u <nome> ou /q para sair"
                    end
                end
                state.input = ""
                update = true
            else
                -- Recebeu EOF (acontece se forçar muito Ctrl+D ou erro de terminal)
                encerrar_sessao(client)
            end
        end
    end
    if update then draw_ui() end
end
