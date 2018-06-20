

if is_apple()
    function _font_paths()
        [
            "/Library/Fonts", # Additional fonts that can be used by all users. This is generally where fonts go if they are to be used by other applications.
            "~/Library/Fonts", # Fonts specific to each user.
            "/Network/Library/Fonts", # Fonts shared for users on a network
        ]
    end
elseif is_windows()
    _font_paths() = [joinpath(ENV["WINDIR"], "fonts")]
else
    function _font_paths()
        [
            "/usr/share/fonts",
            "~/.fonts",
            "/usr/local/share/fonts",
        ]
    end
end


freetype_extensions() = (".FON", ".OTC", ".FNT", ".BDF", ".PFR", ".OTF", ".TTF", ".TTC", ".CFF", ".WOFF")
function freetype_can_read(font::String)
    fontname, ext = splitext(font)
    uppercase(ext) in freetype_extensions()
end

const loaded_fonts = Ptr{FreeType.FT_FaceRec}[]

function loaded_faces()
    if isempty(loaded_fonts)
        for path in fontpaths()
            for font in readdir(path)
                # There doesn't really seem to be a reliable pattern here.
                # there are fonts that should be supported and dont load
                # and fonts with an extension not on the FreeType website, which
                # load just fine. So we just try catch it!
                #freetype_can_read(font) || continue
                fpath = joinpath(path, font)
                try
                    push!(loaded_fonts, newface(fpath)[1])
                end
            end
        end
    end
    return loaded_fonts
end

function findfont(name::String; italic = false, bold = false)
    for face in loaded_faces()
        ft_rect = unsafe_load(face)
        fname = lowercase(unsafe_string(ft_rect.family_name))
        italic = italic == ((ft_rect.style_flags & FreeType.FT_STYLE_FLAG_ITALIC) > 0)
        bold = bold == ((ft_rect.style_flags & FreeType.FT_STYLE_FLAG_BOLD) > 0)
        if contains(fname, lowercase(name)) # && italic && bold 
            return face
        end
    end
    return nothing
end
