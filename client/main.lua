local socket = require("socket")

-- =========================================================
-- 1. CONFIGURAÇÕES E CONSTANTES (Imutáveis)
-- =========================================================
local CONST = {
    HOST_DEFAULT = "localhost",
    PORT_DEFAULT = 8080,
    TIMEOUT_CONNECT = 5,
    WIDTH = 80,
    HEIGHT = 24,
    SIDEBAR_W = 20,
    REFRESH_RATE = 0.05
}

-- Paleta Catppuccin Mocha (Cacheada em locais para performance)
local C = {
    bg      = "\27[48;2;30;30;46m",
    fg      = "\27[38;2;205;214;244m",
    border  = "\27[38;2;88;91;112m",
    accent  = "\27[38;2;203;166;247m",
    user    = "\27[38;2;137;180;250m",
    msg_in  = "\27[38;2;166;227;161m",
    msg_out = "\27[38;2;249;226;175m",
    err     = "\27[38;2;243;139;168m",
    dim     = "\27[38;2;147;153;178m",
    reset   = "\27[0m",
    clear   = "\27[2J\27[H"
}

local BOX = { h = "─", v = "│", tl = "┌", tr = "┐", bl = "└", br = "┘", t_down = "┬", t_up = "┴" }

-- =========================================================
-- 2. UTILITÁRIOS DE SISTEMA
-- =========================================================

-- Hack para o socket.select aceitar stdin no Linux
local stdin_mock = {
    getfd = function() return 0 end,
    dirty = function() return false end
}

local function setup_terminal()
    os.execute("stty -isig") -- Desativa SIGINT (Ctrl+C)
end

local function restore_terminal()
    os.execute("stty isig")
end

local function escape_shell(texto)
    return string.format("%q", texto)
end

local function notificar(usuario, msg)
    -- Executa em background (&) para não travar o loop
    local cmd = string.format("notify-send -a Deepconn -u normal %s %s &",
        escape_shell("De: " .. usuario), escape_shell(msg))
    os.execute(cmd)
end

-- =========================================================
-- 3. MOTOR DE RENDERIZAÇÃO (BUFFERIZADO)
-- =========================================================
-- Otimização: Gera toda a string da tela na memória antes de imprimir
local function render_frame(state, username)
    local buffer = {}
    local chat_w = CONST.WIDTH - CONST.SIDEBAR_W - 3

    -- Helper para mover cursor na string
    local function mv(x, y) return string.format("\27[%d;%dH", y, x) end

    -- 1. Limpa tela
    table.insert(buffer, C.clear)

    -- 2. Header
    local title = " DCNN "
    local h_line = string.rep(BOX.h, 2) .. C.accent .. title .. C.border .. string.rep(BOX.h, CONST.WIDTH - 4 - #title)
    table.insert(buffer, mv(1, 1) .. C.border .. BOX.tl .. h_line:sub(1, CONST.WIDTH + #C.accent) .. BOX.tr .. C.reset)

    -- 3. Colunas Verticais e Rodapé
    for y = 2, CONST.HEIGHT - 1 do
        table.insert(buffer,
            mv(1, y) ..
            C.border .. BOX.v .. string.rep(" ", CONST.SIDEBAR_W) .. BOX.v .. string.rep(" ", chat_w) .. BOX.v .. C
            .reset)
    end

    local bot = string.rep(BOX.h, CONST.SIDEBAR_W) .. BOX.t_up .. string.rep(BOX.h, chat_w)
    table.insert(buffer, mv(1, CONST.HEIGHT) .. C.border .. BOX.bl .. bot .. BOX.br .. C.reset)

    -- 4. Lista de Usuários (Sidebar)
    table.insert(buffer, mv(2, 2) .. C.dim .. "NODES" .. C.reset)
    for i, u in ipairs(state.users) do
        if i + 2 >= CONST.HEIGHT then break end
        local prefix = (u == state.target) and (C.accent .. "> ") or (C.user .. "  ")
        local name_cut = u:sub(1, CONST.SIDEBAR_W - 2)
        table.insert(buffer, mv(2, i + 2) .. prefix .. name_cut .. C.reset)
    end

    -- 5. Chat Header
    table.insert(buffer, mv(CONST.SIDEBAR_W + 3, 2))
    if state.target then
        table.insert(buffer, C.accent .. "@" .. state.target .. C.reset)
    else
        table.insert(buffer, C.err .. "No Channel" .. C.reset)
    end
    table.insert(buffer, mv(CONST.SIDEBAR_W + 3, 3) .. C.dim .. state.system_msg:sub(1, chat_w) .. C.reset)

    -- 6. Mensagens
    local max_lines = CONST.HEIGHT - 5
    local start_idx = math.max(1, #state.messages - max_lines + 1)
    local cy = 4

    for i = start_idx, #state.messages do
        local m = state.messages[i]
        local show = (m.target == "GLOBAL") or (m.sender == state.target) or
        (m.sender == "Eu" and m.target == state.target)

        if show then
            local txt = m.text:sub(1, chat_w - 2)
            local line_fmt
            if m.sender == "Eu" then
                line_fmt = C.msg_out .. "< Me: " .. C.fg .. txt .. C.reset
            else
                line_fmt = C.msg_in .. "> " .. m.sender .. ": " .. C.fg .. txt .. C.reset
            end
            table.insert(buffer, mv(CONST.SIDEBAR_W + 3, cy) .. line_fmt)
            cy = cy + 1
        end
    end

    -- 7. Input
    table.insert(buffer, mv(1, CONST.HEIGHT + 1) .. C.accent .. "CMD > " .. C.reset .. state.input)

    -- FLUSH ÚNICO (Muito mais rápido)
    io.write(table.concat(buffer))
    io.flush()
end

-- =========================================================
-- 4. LÓGICA DE REDE E CONTROLE
-- =========================================================

local function safe_exit(client, msg)
    if client then
        client:settimeout(nil) -- Bloqueia para garantir envio
        pcall(function() client:send("DESCONECTADO\n") end)
        client:close()
    end
    restore_terminal()
    io.write(C.clear)
    print(C.accent .. ">>> " .. (msg or "Deepconn Encerrado.") .. C.reset)
    os.exit()
end

local function conectar()
    io.write(C.clear .. C.accent .. ">>> DEEPCONN v2.0 OPTIMIZED" .. C.reset .. "\n")

    io.write(C.user .. "User: " .. C.reset)
    local user = io.read()
    if not user then
        restore_terminal(); os.exit()
    end

    io.write(C.user .. "IP [localhost]: " .. C.reset)
    local ip = io.read()
    if ip == "" then ip = CONST.HOST_DEFAULT end

    io.write(C.user .. "Port [8080]: " .. C.reset)
    local port = io.read()
    if port == "" then port = CONST.PORT_DEFAULT end

    -- Detecção IPv6 vs IPv4
    local client
    if ip:find(":") then
        client = socket.tcp6()
    else
        client = socket.tcp()
    end

    client:settimeout(CONST.TIMEOUT_CONNECT)
    local ok, err = client:connect(ip, port)

    if not ok then
        print(C.err .. "Falha na conexão: " .. err .. C.reset)
        restore_terminal()
        os.exit(1)
    end

    client:send(user .. "\n")
    client:settimeout(0) -- Non-blocking
    return client, user
end

-- =========================================================
-- 5. MAIN LOOP
-- =========================================================
local function main()
    setup_terminal()

    local client, username = conectar()

    local state = {
        users = {},
        messages = {},
        target = nil,
        input = "",
        system_msg = "Pronto."
    }

    render_frame(state, username)

    while true do
        local read_sockets = { client, stdin_mock }
        local ready = socket.select(read_sockets, nil, CONST.REFRESH_RATE)
        local needs_update = false

        for _, s in ipairs(ready) do
            -- --- DADOS DA REDE ---
            if s == client then
                local line, err = client:receive()
                if not err then
                    -- Parsing Otimizado
                    local cmd, payload = line:match("^(%u+)%s+(.+)")

                    if cmd == "LISTA" then
                        state.users = {}
                        for u in payload:gmatch("([^,]+)") do
                            if u ~= username then table.insert(state.users, u) end
                        end
                        needs_update = true
                    elseif cmd == "MSG" then
                        local remetente, msg = payload:match("^([^ ]+) (.+)")
                        if remetente then
                            table.insert(state.messages, { sender = remetente, text = msg, target = "Eu" })
                            if not state.target then state.target = remetente end
                            notificar(remetente, msg)
                            needs_update = true
                        end
                    end
                else
                    safe_exit(client, "Conexão perdida com o servidor.")
                end

                -- --- INPUT DO TECLADO ---
            elseif s == stdin_mock then
                local txt = io.read()
                if txt then
                    if txt:sub(1, 1) == "/" then
                        -- Comandos
                        if txt:match("^/u ") then
                            state.target = txt:sub(4)
                            state.system_msg = "Falando com: " .. state.target
                        elseif txt == "/q" or txt == "/quit" then
                            safe_exit(client)
                        end
                    else
                        -- Envio de Mensagem
                        if state.target then
                            client:send("MSG " .. state.target .. " " .. txt .. "\n")
                            table.insert(state.messages, { sender = "Eu", text = txt, target = state.target })
                        else
                            state.system_msg = "ERRO: Use /u <nome>"
                        end
                    end
                    state.input = ""
                    needs_update = true
                else
                    safe_exit(client) -- EOF
                end
            end
        end

        if needs_update then
            render_frame(state, username)
        end
    end
end

-- Proteção para garantir que o terminal restaure se o script crashar feio
if not pcall(main) then
    restore_terminal()
    print("\nErro crítico executando Deepconn.")
end
