function findfont(; printresult::Bool = false, kwargs...)
    isempty(kwargs) && error("You have to specify at least one font attribute.")
    kwargs = convert(Dict, kwargs)

    function tryconvert(type, value, attr)
        try
            return convert(type, value)
        catch
            error("""The font attribute "$attr" must be of type $type or convertible to it.
            The given value "$value" of type $(typeof(value)) is not.""")
        end
    end

    # check attributes because fontconfig errors are cryptic
    for (attr, value) in kwargs
        if attr in string_attrs
            kwargs[attr] = tryconvert(String, value, attr)
        elseif attr in double_attrs
            kwargs[attr] = tryconvert(Float64, value, attr)
        elseif attr in integer_attrs
            kwargs[attr] = tryconvert(Int64, value, attr)
        elseif attr in bool_attrs
            kwargs[attr] = tryconvert(Bool, value, attr)
        else
            error("""There is no font attribute "$attr".""")
        end
    end

    searchpattern = Pattern(; kwargs...)
    foundpattern = match(searchpattern)
    fontpath = format(foundpattern, "%{file}")
    fontface = newface(fontpath)[]

    if printresult
        println("Best matching font: ", format(foundpattern, "%{fullname}"))
    end

    fontface
end
