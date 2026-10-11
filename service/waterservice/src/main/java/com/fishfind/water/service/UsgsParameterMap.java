package com.fishfind.water.service;

import java.util.Map;

/**
 * Maps a USGS Water Data API {@code parameter_code} to the name/unit pair the legacy WaterServices feed
 * published for it, which is what {@code dbo.sp_push_us_water_data} keys its column mapping and unit
 * conversions on.
 *
 * <p>The pairs are exactly what the old WaterML parser produced: {@code variableName} split at the first
 * comma, trimmed, with {@code &#179;} rewritten to {@code ^3}. They were harvested from live legacy
 * responses for eight states on 2026-10-11 so the move to the new API changes no stored value. Some legacy
 * units do not match the procedure's conversion checks (for example {@code in ft}, and
 * {@code water, &#176;C} for temperature); that is pre-existing behaviour, kept on purpose.
 *
 * <p>Codes not listed here are not pushed: the procedure has no column for them.
 */
public final class UsgsParameterMap {

    /**
     * Legacy WaterML name and unit for one parameter code.
     *
     * @param name variable name, for example {@code Streamflow}
     * @param unit variable unit, for example {@code ft^3/s}
     */
    public record LegacyName(String name, String unit) {
    }

    private static final Map<String, LegacyName> MAP = Map.ofEntries(
            Map.entry("00010", new LegacyName("Temperature", "water, &#176;C")),
            Map.entry("00011", new LegacyName("Temperature", "water, &#176;F")),
            Map.entry("00020", new LegacyName("Temperature", "air, &#176;C")),
            Map.entry("00021", new LegacyName("Temperature", "air, &#176;F")),
            Map.entry("00025", new LegacyName("Barometric pressure", "mmHg")),
            Map.entry("00030", new LegacyName("Incident solar radiation intensity", "(cal/cm&#178;)/d")),
            Map.entry("00035", new LegacyName("Wind speed", "mph")),
            Map.entry("00036", new LegacyName("Wind direction", "degrees clockwise from north")),
            Map.entry("00045", new LegacyName("Precipitation", "total, in")),
            Map.entry("00047", new LegacyName("Total partial pressure of dissolved gases", "water, unfiltered, mmHg")),
            Map.entry("00048", new LegacyName("Total partial pressure of dissolved gases", "water, unfiltered, percent of saturation")),
            Map.entry("00052", new LegacyName("Relative humidity", "percent")),
            Map.entry("00053", new LegacyName("Surface area", "acres")),
            Map.entry("00054", new LegacyName("Reservoir storage", "acre-ft")),
            Map.entry("00055", new LegacyName("Stream velocity", "ft/s")),
            Map.entry("00058", new LegacyName("Flow rate of well", "gal/min")),
            Map.entry("00060", new LegacyName("Streamflow", "ft^3/s")),
            Map.entry("00062", new LegacyName("Elevation of reservoir water surface above datum", "ft")),
            Map.entry("00065", new LegacyName("Gage height", "ft")),
            Map.entry("00095", new LegacyName("Specific conductance", "water, unfiltered, microsiemens per centimeter at 25&#176;C")),
            Map.entry("00300", new LegacyName("Dissolved oxygen", "water, unfiltered, mg/L")),
            Map.entry("00301", new LegacyName("Dissolved oxygen", "water, unfiltered, % saturation")),
            Map.entry("00400", new LegacyName("pH", "water, unfiltered, field, standard units")),
            Map.entry("00480", new LegacyName("Salinity", "water, unfiltered, parts per thousand")),
            Map.entry("00671", new LegacyName("Orthophosphate", "water, filtered, mg/L as P")),
            Map.entry("32295", new LegacyName("Colored dissolved organic matter (CDOM)", "water, in situ, single band excitation, fluorescence emission, ppb QSE")),
            Map.entry("32315", new LegacyName("Chlorophyll <i>a</i>", "estimated, water, in-situ, in-vivo fluorescence (IVF), relative fluorescence units (RFU)")),
            Map.entry("32316", new LegacyName("Chlorophyll <i>a</i>", "estimated, water, in-situ, in-vivo fluorescence (IVF), concentration estimated from reference material, micrograms per liter")),
            Map.entry("32317", new LegacyName("Chlorophyll <i>a</i>", "modeled, water, in-situ, in-vivo fluorescence (IVF), concentration modeled from field samples analyzed by extraction, micrograms per liter")),
            Map.entry("32319", new LegacyName("Phycocyanins (cyanobacteria)", "water, in situ, fluorometric method, excitation at 590 &#177;15 nm, emission at 685 &#177;20 nm, micrograms per liter")),
            Map.entry("32321", new LegacyName("Phycocyanins (cyanobacteria)", "water, in situ, fluorometric method, excitation at 590 &#177;15 nm, emission at 685 &#177;20 nm, relative fluorescence units (RFU)")),
            Map.entry("32322", new LegacyName("Colored dissolved organic matter (CDOM)", "water, in situ, fluorometric method, relative fluorescence units (RFU)")),
            Map.entry("32323", new LegacyName("Phycoerythrin (blue-green algae)", "water, in situ, fluorometric method, relative fluorescence units (RFU)")),
            Map.entry("32336", new LegacyName("Phycoerythrin fluorescence (fPE)", "water, in situ, micrograms per liter as phycoerythrin")),
            Map.entry("32360", new LegacyName("Fluorescence", "water, in situ, excitation 360-370, emission 440-520, micrograms per liter as quinine sulfate equivalents (QSE)")),
            Map.entry("45592", new LegacyName("Gate opening", "height, ft")),
            Map.entry("50012", new LegacyName("Compaction", "aquifer system, feet")),
            Map.entry("50042", new LegacyName("Streamflow", "gal/min")),
            Map.entry("61727", new LegacyName("Wind gust speed", "air, kn")),
            Map.entry("61728", new LegacyName("Wind gust speed", "air, mph")),
            Map.entry("61729", new LegacyName("Wind gust direction", "air, degrees clockwise from true north")),
            Map.entry("62361", new LegacyName("Chlorophylls", "water, fluorometric, 650-700 nm, in situ sensor, micrograms per liter")),
            Map.entry("62607", new LegacyName("Barometric pressure", "uncorrected, kPa")),
            Map.entry("62608", new LegacyName("Total solar radiation (direct + diffuse radiation on a horizontal surface)", "downward intensity, watts/m&#178;")),
            Map.entry("62609", new LegacyName("Net solar radiation", "W/m&#178;")),
            Map.entry("62610", new LegacyName("Groundwater level above NGVD 1929", "feet")),
            Map.entry("62611", new LegacyName("Groundwater level above NAVD 1988", "ft")),
            Map.entry("62614", new LegacyName("Lake or reservoir water surface elevation above NGVD 1929", "ft")),
            Map.entry("62615", new LegacyName("Lake or reservoir water surface elevation above NAVD 1988", "ft")),
            Map.entry("62616", new LegacyName("Lake or reservoir water surface elevation above NGVD 1929", "m")),
            Map.entry("62619", new LegacyName("Estuary or ocean water surface elevation above NGVD 1929", "ft")),
            Map.entry("62620", new LegacyName("Estuary or ocean water surface elevation above NAVD 1988", "ft")),
            Map.entry("62625", new LegacyName("Wind speed", "m/s")),
            Map.entry("62967", new LegacyName("Soil-heat flux", "W/m&#178;")),
            Map.entry("62968", new LegacyName("Latent heat flux", "W/m&#178;")),
            Map.entry("62969", new LegacyName("Sensible heat flux", "W/m&#178;")),
            Map.entry("63158", new LegacyName("Stream water level elevation above NGVD 1929", "in ft")),
            Map.entry("63160", new LegacyName("Stream water level elevation above NAVD 1988", "in ft")),
            Map.entry("63680", new LegacyName("Turbidity", "water, unfiltered, monochrome near infra-red LED light, 780-900 nm, detection angle 90 &#177;2.5&#176;, formazin nephelometric units (FNU)")),
            Map.entry("63682", new LegacyName("Turbidity", "water, unfiltered, monochrome near infra-red LED light source, 780-900 nm, detection angle 0-45&#176; to incident light (backscatter), FBU")),
            Map.entry("70227", new LegacyName("Direction of stream flow", "magnetic azimuth, degrees")),
            Map.entry("70232", new LegacyName("Water velocity reading from field sensor", "knots")),
            Map.entry("70301", new LegacyName("Residue", "water, filtered, sum of constituents, mg/L")),
            Map.entry("70369", new LegacyName("Suspended sediment particles between 0.50 to 16.00 microns", "water, unfiltered, computed by regression equation, counts per liter")),
            Map.entry("70969", new LegacyName("DCP battery voltage", "V")),
            Map.entry("72019", new LegacyName("Depth to water level", "ft below land surface")),
            Map.entry("72020", new LegacyName("Elevation above NGVD 1929", "ft")),
            Map.entry("72036", new LegacyName("Reservoir storage", "thousand acre feet")),
            Map.entry("72125", new LegacyName("Atmospheric water vapor pressure", "calculated, kilopascals")),
            Map.entry("72137", new LegacyName("Streamflow", "tidally filtered, ft^3/s")),
            Map.entry("72147", new LegacyName("Depth of sensor below water surface", "feet")),
            Map.entry("72148", new LegacyName("Depth of sensor below water surface", "meters")),
            Map.entry("72181", new LegacyName("Moisture content", "soil, volumetric, fraction of total volume")),
            Map.entry("72189", new LegacyName("Snow depth", "meters")),
            Map.entry("72192", new LegacyName("Precipitation", "cumulative, inches")),
            Map.entry("72199", new LegacyName("Water depth", "water surface to bottom, feet")),
            Map.entry("72205", new LegacyName("Bulk electrical conductance", "soil, decisiemens per meter")),
            Map.entry("72214", new LegacyName("Lake or reservoir elevation above International Great Lakes Datum (IGLD)", "feet")),
            Map.entry("72238", new LegacyName("Sediment corrected acoustic backscatter (SCB)", "decibels")),
            Map.entry("72251", new LegacyName("Water level above marsh", "feet")),
            Map.entry("72252", new LegacyName("Solar radiation (average flux density on a horizontal surface during measurement interval)", "kW/m&#178;")),
            Map.entry("72253", new LegacyName("Soil temperature", "degrees Celsius")),
            Map.entry("72254", new LegacyName("Water velocity reading from field sensor", "feet per second")),
            Map.entry("72255", new LegacyName("Mean water velocity for discharge computation", "feet per second")),
            Map.entry("72264", new LegacyName("Lake or reservoir elevation above New York State Barge Canal Datum (NYBCD)", "feet")),
            Map.entry("72269", new LegacyName("Wind gust speed", "air, meters per second")),
            Map.entry("72275", new LegacyName("Lake or reservoir elevation above United States Bureau of Reclamation Klamath Basin (USBRKB) Datum", "feet")),
            Map.entry("72279", new LegacyName("Tidal elevation", "NOS-averaged, NAVD88, feet")),
            Map.entry("72294", new LegacyName("Mean water velocity for discharge computation", "miles per hour")),
            Map.entry("72322", new LegacyName("Surface velocity at point in stream", "feet per second")),
            Map.entry("72330", new LegacyName("Stream bed elevation at measurement point", "NAVD88, feet")),
            Map.entry("72335", new LegacyName("Elevation above NAVD 1988", "feet")),
            Map.entry("72337", new LegacyName("Turbidity", "water, unfiltered, monochrome near infra-red LED light, 780-900 nm, detection angle 135-180 degrees, SDVB (styrene divinylbenzene beads) backscatter units (SBU)")),
            Map.entry("72341", new LegacyName("Water content of snow", "mm")),
            Map.entry("72358", new LegacyName("Evapotranspiration rate", "millimeters per hour")),
            Map.entry("72375", new LegacyName("Lake or reservoir elevation above local mean sea level (LMSL)", "feet")),
            Map.entry("72401", new LegacyName("Salinity", "water, in situ, tidally filtered, practical salinity units at 25 degrees Celsius")),
            Map.entry("72412", new LegacyName("Barometric pressure", "uncorrected, hectopascals")),
            Map.entry("72431", new LegacyName("Cosmic ray neutron", "count")),
            Map.entry("72443", new LegacyName("Fluorescence", "water, in situ, excitation 360-370, emission 440-520, uncorrected for water temperature, turbidity or inner filter effects, micrograms per liter as quinine sulfate equivalents (QSE)")),
            Map.entry("74207", new LegacyName("Moisture content", "soil, volumetric, percent of total volume")),
            Map.entry("75969", new LegacyName("Barometric pressure", "not corrected to sea level, mbar")),
            Map.entry("80154", new LegacyName("Suspended sediment concentration", "mg/L")),
            Map.entry("80297", new LegacyName("Suspended sediment load", "water, unfiltered, computed, the product of regression-computed suspended sediment concentration and streamflow, tons per day")),
            Map.entry("80299", new LegacyName("Suspended sediment concentration", "from uncalibrated sensor, milligrams per liter")),
            Map.entry("80300", new LegacyName("Suspended sediment concentration", "water, unfiltered, at a fixed point in stream, estimated by a regression equation with turbidity, milligrams per liter")),
            Map.entry("81903", new LegacyName("Depth to bottom at sample location", "feet")),
            Map.entry("82047", new LegacyName("Depth to top of sampling interval", "meters")),
            Map.entry("82127", new LegacyName("Wind speed", "knots")),
            Map.entry("90860", new LegacyName("Salinity", "water, unfiltered, practical salinity units at 25&#176;C")),
            Map.entry("95204", new LegacyName("Phycocyanins (cyanobacteria)", "water, in situ, IVF, IVFU")),
            Map.entry("99064", new LegacyName("Water surface elevation difference between two locations", "feet")),
            Map.entry("99067", new LegacyName("Difference between observed and predicted water surface elevation", "feet")),
            Map.entry("99133", new LegacyName("Nitrate plus nitrite", "water, in situ, mg/L as N")),
            Map.entry("99137", new LegacyName("Nitrate", "water, in situ, mg/L as N")),
            Map.entry("99220", new LegacyName("Chloride", "water, unfiltered, mg/L")),
            Map.entry("99234", new LegacyName("Count of samples collected by autosampler", "number")),
            Map.entry("99238", new LegacyName("Location of Acoustic Doppler Velocity Meter cell end", "feet")),
            Map.entry("99246", new LegacyName("Upper 90 percent prediction limit for SSC by regression (PCODE 99409)", "milligrams per liter")),
            Map.entry("99247", new LegacyName("Lower 90 percent prediction limit for SSC by regression (PCODE 99409)", "milligrams per liter")),
            Map.entry("99252", new LegacyName("Upper 90 percent prediction limit for suspended sediment load by regression (PCODE 80297)", "tons per day")),
            Map.entry("99253", new LegacyName("Lower 90 percent prediction limit for suspended sediment load by regression (PCODE 80297)", "tons per day")),
            Map.entry("99268", new LegacyName("Depth of sensor below water surface", "not corrected for barometric pressure variations, feet")),
            Map.entry("99269", new LegacyName("Depth of sensor below water surface", "not corrected for barometric pressure variations, meters")),
            Map.entry("99409", new LegacyName("Suspended sediment concentration", "water, unfiltered, estimated by regression equation, mg/L")),
            Map.entry("99970", new LegacyName("Instrument pitch (front to back movement)", "units specified in data descriptor")),
            Map.entry("99971", new LegacyName("Instrument roll (side to side movement)", "units specified in data descriptor")),
            Map.entry("99998", new LegacyName("Photosynthetically active radiation (PAR)", "water, in situ, micromoles of photons per square meter per second"))
    );

    private UsgsParameterMap() {
    }

    /**
     * Returns the legacy name/unit for a parameter code.
     *
     * @param parameterCode USGS parameter code
     * @return the legacy pair, or {@code null} when the code is not mapped
     */
    public static LegacyName find(String parameterCode) {
        return parameterCode == null ? null : MAP.get(parameterCode);
    }
}
