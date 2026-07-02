// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Units — the single source of truth for the curated unit catalogue, shared by
// the ConverterView pickers and the Calculator's unit autocomplete / picker.
// `value` is the canonical libqalculate-parseable form that gets inserted;
// `label` is what we show; `aliases` are extra spellings that only help matching
// (the user may type "ft"/"feet" for foot) — they need not parse on their own.

pragma Singleton

import QtQuick

QtObject {
    id: root

    readonly property var categories: [
        { name: i18nc("@title unit category", "Area"), units: [
            {label: "m²", value: "m^2", aliases: ["m2", "sqm", "square meter", "square metre"]},
            {label: "km²", value: "km^2", aliases: ["km2", "sqkm", "square kilometer"]},
            {label: "cm²", value: "cm^2", aliases: ["cm2", "sqcm"]},
            {label: "hectare", value: "hectare", aliases: ["ha", "hectares"]},
            {label: "acre", value: "acre", aliases: ["acres"]},
            {label: "mi²", value: "mile^2", aliases: ["mi2", "sqmi", "square mile"]},
            {label: "ft²", value: "ft^2", aliases: ["ft2", "sqft", "square foot", "square feet"]},
            {label: "in²", value: "inch^2", aliases: ["in2", "sqin", "square inch"]} ] },
        { name: i18nc("@title unit category", "Length"), units: [
            {label: "m", value: "meter", aliases: ["metre", "meters", "metres"]},
            {label: "km", value: "km", aliases: ["kilometer", "kilometre", "kilometers", "kilometres"]},
            {label: "cm", value: "cm", aliases: ["centimeter", "centimetre"]},
            {label: "mm", value: "mm", aliases: ["millimeter", "millimetre"]},
            {label: "mile", value: "mile", aliases: ["mi", "miles"]},
            {label: "yard", value: "yard", aliases: ["yd", "yards"]},
            {label: "foot", value: "foot", aliases: ["ft", "feet"]},
            {label: "inch", value: "inch", aliases: ["in", "inches"]},
            {label: "nautical mile", value: "nmi", aliases: ["nmi", "nautical miles"]} ] },
        { name: i18nc("@title unit category", "Temperature"), units: [
            {label: "°C", value: "celsius", aliases: ["celsius", "centigrade", "degC", "C"]},
            {label: "°F", value: "fahrenheit", aliases: ["fahrenheit", "degF", "F"]},
            {label: "K", value: "kelvin", aliases: ["kelvins"]} ] },
        { name: i18nc("@title unit category", "Volume"), units: [
            {label: "L", value: "L", aliases: ["liter", "litre", "liters", "litres"]},
            {label: "mL", value: "mL", aliases: ["milliliter", "millilitre"]},
            {label: "m³", value: "m^3", aliases: ["m3", "cubic meter", "cubic metre"]},
            {label: "cm³", value: "cm^3", aliases: ["cm3", "cc", "cubic centimeter"]},
            {label: "gallon", value: "gallon", aliases: ["gal", "gallons"]},
            {label: "quart", value: "quart", aliases: ["qt", "quarts"]},
            {label: "pint", value: "pint", aliases: ["pt", "pints"]},
            {label: "cup", value: "cup", aliases: ["cups"]},
            {label: "fl oz", value: "floz", aliases: ["fluid ounce", "floz"]},
            {label: "ft³", value: "ft^3", aliases: ["ft3", "cubic foot", "cubic feet"]} ] },
        { name: i18nc("@title unit category", "Mass"), units: [
            {label: "kg", value: "kg", aliases: ["kilogram", "kilograms", "kilo", "kilos"]},
            {label: "g", value: "g", aliases: ["gram", "grams", "gramme"]},
            {label: "mg", value: "mg", aliases: ["milligram", "milligrams"]},
            {label: "tonne", value: "tonne", aliases: ["tonnes", "metric ton"]},
            {label: "lb", value: "lb", aliases: ["pound", "pounds", "lbs"]},
            {label: "oz", value: "oz", aliases: ["ounce", "ounces"]},
            {label: "stone", value: "stone", aliases: ["stones", "st"]} ] },
        { name: i18nc("@title unit category", "Data"), units: [
            {label: "byte", value: "byte", aliases: ["bytes"]},
            {label: "bit", value: "bit", aliases: ["bits"]},
            {label: "kB", value: "kB", aliases: ["kilobyte", "kilobytes"]},
            {label: "MB", value: "MB", aliases: ["megabyte", "megabytes"]},
            {label: "GB", value: "GB", aliases: ["gigabyte", "gigabytes"]},
            {label: "TB", value: "TB", aliases: ["terabyte", "terabytes"]},
            {label: "KiB", value: "KiB", aliases: ["kibibyte"]},
            {label: "MiB", value: "MiB", aliases: ["mebibyte"]},
            {label: "GiB", value: "GiB", aliases: ["gibibyte"]},
            {label: "TiB", value: "TiB", aliases: ["tebibyte"]} ] },
        { name: i18nc("@title unit category", "Speed"), units: [
            {label: "m/s", value: "m/s", aliases: ["mps", "meters per second"]},
            {label: "km/h", value: "km/h", aliases: ["kmh", "kph", "kilometers per hour"]},
            {label: "mph", value: "mph", aliases: ["miles per hour"]},
            {label: "knot", value: "knot", aliases: ["knots", "kn"]},
            {label: "ft/s", value: "ft/s", aliases: ["fps", "feet per second"]} ] },
        { name: i18nc("@title unit category", "Time"), units: [
            {label: "ms", value: "ms", aliases: ["millisecond", "milliseconds", "msec"]},
            {label: "second", value: "s", aliases: ["sec", "secs", "seconds"]},
            {label: "minute", value: "min", aliases: ["mins", "minutes"]},
            {label: "hour", value: "h", aliases: ["hr", "hrs", "hours"]},
            {label: "day", value: "day", aliases: ["days"]},
            {label: "week", value: "week", aliases: ["wk", "weeks"]},
            {label: "month", value: "month", aliases: ["months"]},
            {label: "year", value: "year", aliases: ["yr", "yrs", "years"]} ] },
        { name: i18nc("@title unit category", "Fuel Economy"), units: [
            {label: "mpg", value: "mpg", aliases: ["miles per gallon"]},
            {label: "km/L", value: "km/L", aliases: ["kmpl", "kml", "kilometers per liter"]},
            {label: "L/100km", value: "L/100km", aliases: ["l100km", "liters per 100km"]} ] },
        { name: i18nc("@title unit category", "Data Rate"), units: [
            {label: "bit/s", value: "bit/s", aliases: ["bps", "bits per second"]},
            {label: "kbit/s", value: "kbit/s", aliases: ["kbps"]},
            {label: "Mbit/s", value: "Mbit/s", aliases: ["mbps"]},
            {label: "Gbit/s", value: "Gbit/s", aliases: ["gbps"]},
            {label: "B/s", value: "B/s", aliases: ["bytes per second"]},
            {label: "kB/s", value: "kB/s", aliases: ["kilobytes per second"]},
            {label: "MB/s", value: "MB/s", aliases: ["megabytes per second"]},
            {label: "GB/s", value: "GB/s", aliases: ["gigabytes per second"]} ] },
        { name: i18nc("@title unit category", "Energy"), units: [
            {label: "J", value: "J", aliases: ["joule", "joules"]},
            {label: "kJ", value: "kJ", aliases: ["kilojoule", "kilojoules"]},
            {label: "cal", value: "cal", aliases: ["calorie", "calories"]},
            {label: "kcal", value: "kcal", aliases: ["kilocalorie", "kilocalories"]},
            {label: "Wh", value: "Wh", aliases: ["watt hour", "watthour"]},
            {label: "kWh", value: "kWh", aliases: ["kilowatt hour", "kilowatthour"]},
            {label: "eV", value: "eV", aliases: ["electronvolt", "electronvolts"]},
            {label: "BTU", value: "Btu", aliases: ["btu", "british thermal unit"]} ] },
        { name: i18nc("@title unit category", "Frequency"), units: [
            {label: "Hz", value: "Hz", aliases: ["hertz"]},
            {label: "kHz", value: "kHz", aliases: ["kilohertz"]},
            {label: "MHz", value: "MHz", aliases: ["megahertz"]},
            {label: "GHz", value: "GHz", aliases: ["gigahertz"]},
            {label: "THz", value: "THz", aliases: ["terahertz"]} ] },
        { name: i18nc("@title unit category", "Angle"), units: [
            {label: "°", value: "deg", aliases: ["degree", "degrees", "deg"]},
            {label: "rad", value: "rad", aliases: ["radian", "radians"]},
            {label: "grad", value: "gradian", aliases: ["grad", "gradians", "gon"]},
            {label: "arcmin", value: "arcmin", aliases: ["arcminute", "arcminutes"]},
            {label: "arcsec", value: "arcsec", aliases: ["arcsecond", "arcseconds"]},
            {label: "turn", value: "turn", aliases: ["turns", "revolution", "revolutions", "rev"]} ] }
    ]

    // All the lowercase forms a unit can be found by (value + label + aliases).
    function _formsOf(u) {
        var forms = [u.value.toLowerCase(), u.label.toLowerCase()];
        if (u.aliases)
            for (var k = 0; k < u.aliases.length; ++k)
                forms.push(u.aliases[k].toLowerCase());
        return forms;
    }

    // Display label for a stored value (falls back to the value itself).
    function labelFor(value) {
        for (var i = 0; i < categories.length; ++i)
            for (var j = 0; j < categories[i].units.length; ++j)
                if (categories[i].units[j].value === value)
                    return categories[i].units[j].label;
        return value;
    }

    // Resolve a detected unit token (abbreviation or name, e.g. "mi"/"mile")
    // to a catalogue `value`, or "" if it isn't in the curated catalogue. Matches
    // exactly (case-insensitive) against each unit's value / label / aliases.
    function resolve(token) {
        var t = (token || "").toLowerCase().trim();
        if (t.length === 0)
            return "";
        for (var i = 0; i < categories.length; ++i)
            for (var j = 0; j < categories[i].units.length; ++j) {
                var forms = _formsOf(categories[i].units[j]);
                for (var k = 0; k < forms.length; ++k)
                    if (forms[k] === t)
                        return categories[i].units[j].value;
            }
        return "";
    }

    // The category name a value belongs to, or "".
    function categoryOf(value) {
        for (var i = 0; i < categories.length; ++i)
            for (var j = 0; j < categories[i].units.length; ++j)
                if (categories[i].units[j].value === value)
                    return categories[i].name;
        return "";
    }

    // A sensible default unit in a category, preferring one != excludeValue.
    function firstCompatible(categoryName, excludeValue) {
        for (var i = 0; i < categories.length; ++i) {
            if (categories[i].name !== categoryName)
                continue;
            var units = categories[i].units;
            for (var j = 0; j < units.length; ++j)
                if (units[j].value !== excludeValue)
                    return units[j].value;
            if (units.length > 0)
                return units[0].value;
        }
        return excludeValue;
    }

    // Full list [{label, value, category}] filtered by any form (value, label,
    // alias) or the category name — used by the grouped pickers.
    function filtered(text) {
        var f = (text || "").toLowerCase();
        var out = [];
        for (var i = 0; i < categories.length; ++i) {
            var c = categories[i];
            for (var j = 0; j < c.units.length; ++j) {
                var u = c.units[j];
                var hit = f.length === 0 || c.name.toLowerCase().indexOf(f) >= 0;
                if (!hit) {
                    var forms = _formsOf(u);
                    for (var k = 0; k < forms.length && !hit; ++k)
                        if (forms[k].indexOf(f) >= 0)
                            hit = true;
                }
                if (hit)
                    out.push({ label: u.label, value: u.value, category: c.name });
            }
        }
        return out;
    }

    // Ranked inline suggestions for a typed token: exact matches first, then
    // prefix, then substring — across value/label/aliases; capped at `limit`.
    function suggest(token, limit) {
        var t = (token || "").toLowerCase();
        if (t.length === 0)
            return [];
        var exact = [];
        var pre = [];
        var sub = [];
        for (var i = 0; i < categories.length; ++i) {
            var c = categories[i];
            for (var j = 0; j < c.units.length; ++j) {
                var u = c.units[j];
                var forms = _formsOf(u);
                var rank = 3;
                for (var k = 0; k < forms.length; ++k) {
                    var idx = forms[k].indexOf(t);
                    if (forms[k] === t) { rank = 0; break; }
                    if (idx === 0) rank = Math.min(rank, 1);
                    else if (idx > 0) rank = Math.min(rank, 2);
                }
                var row = { label: u.label, value: u.value, category: c.name };
                if (rank === 0) exact.push(row);
                else if (rank === 1) pre.push(row);
                else if (rank === 2) sub.push(row);
            }
        }
        var outList = exact.concat(pre).concat(sub);
        if (limit && limit > 0 && outList.length > limit)
            outList = outList.slice(0, limit);
        return outList;
    }
}
