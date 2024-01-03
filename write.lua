local function set_item_first(ast)
    for i, v in ipairs(ast) do
        local t = v.type
        if t == "enum" or t == "item" then
            -- check if it is the first item/enum of that level
            if i == 1 then
                v.first = true
            else
                for j = i - 1, 1, -1 do
                    if ast[j].type ~= "item" and ast[j].type ~= "enum" then
                        v.first = true
                        break
                    elseif ast[j].type == t and ast[j].level == v.level then
                        v.first = false
                        break
                    elseif ast[j].level < v.level then
                        v.first = true
                        break
                    end
                end
            end
        end
    end
end

local function set_item_last(ast)
    local len = #ast
    for i, v in ipairs(ast) do
        local t = v.type
        if t == "enum" or t == "item" then
            -- check if it is the last item/enum of that level
            if i == len then
                v.last = true
            else
                for j = i + 1, len do
                    if ast[j].type ~= "item" and ast[j].type ~= "enum" then
                        v.last = true
                        break
                    elseif ast[j].type == t and ast[j].level == v.level then
                        v.last = false
                        break
                    elseif ast[j].level < v.level then
                        v.last = true
                        break
                    end
                end
            end
        end
    end
end

--[[
elements:
- header
- latex environment
- item
- enum
- code
- other
- citation
- verbatim
- math
- latex_cmd
- italic
- bold
- text
--]]



local function walk(ast, out, config)
    if ast.type == nil then
        for _, v in ipairs(ast) do
            walk(v, out, config)
        end
    else
        if ast.type == "header" then
            out[1] = out[1] .. "\n\\"
	    if ast.level > #config.header then
		    ast.level = #config.header -- max level
	    end
	    out[1] = out[1] .. config.header[ast.level]

            out[1] = out[1] .. "{"
            walk(ast.content, out, config)
            out[1] = out[1] .. "}"

        elseif ast.type == "latex" then
            out[1] = out[1] .. "\n" .. ast.content

        elseif ast.type == "item" then
            if ast.first then
                out[1] = out[1] .. "\n\\begin{itemize}"
            end
            out[1] = out[1] .. "\n\\item "
            walk(ast.content, out, config)
            if ast.last then
                out[1] = out[1] .. "\n\\end{itemize}"
            end
        
        elseif ast.type == "enum" then  -- TODO: add 
            if ast.first then
                out[1] = out[1] .. "\n\\begin{enumerate}"
            end
            out[1] = out[1] .. "\n\\item" -- TODO: the space after \item is not always needed
            walk(ast.content, out, config)
            if ast.last then
                out[1] = out[1] .. "\n\\end{enumerate}"
            end

        elseif ast.type == "code" then
            -- TODO: add code type
            out[1] = out[1] .. "\n\\begin{verbatim}\n" .. ast.content .. "\\end{verbatim}"
        
        elseif ast.type == "other" then
            walk(ast.content, out, config)
        
        elseif ast.type == "citation" then
            out[1] = out[1] .. "\\cite{" .. table.concat(ast.content, ", ") .. "}"

        elseif ast.type == "verbatim" then
            out[1] = out[1] .. "\\texttt{" .. ast.content .. "}"

        elseif ast.type == "math" or ast.type == "latex_cmd" then
            out[1] = out[1] .. ast.content

        elseif ast.type == "italic" then
            out[1] = out[1] .. "\\emph{"
            walk(ast.content, out, config)
            out[1] = out[1] .. "}"
        
        elseif ast.type == "bold" then
            out[1] = out[1] .. "\\textbf{"
            walk(ast.content, out, config)
            out[1] = out[1] .. "}"

	elseif ast.type == "strikethrough" then
	    out[1] = out[1] .. "\\sout{"
	    walk(ast.content, out, config)
	    out[1] = out[1] .. "}"

        elseif ast.type == "text" then
            out[1] = out[1] .. ast.content
        else
            error("Unknown type: " .. ast.type)
        end
    end
end

local function write(ast, config)
    set_item_first(ast)
    set_item_last(ast)

    local output = {""}
    walk(ast, output, config)
    return output[1]:sub(2) -- remove first newline that was added
end

return write

