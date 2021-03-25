//-----------------------------------------------------------------------------
// Configuration
//-----------------------------------------------------------------------------

namespace UnityEngine.Rendering.HighDefinition
{
    /// <summary>
    /// Project-wide shader configuration options.
    /// </summary>
    /// <remarks>This enum will generate the proper shader defines.</remarks>
    ///<seealso cref="ShaderConfig"/>
    [GenerateHLSL(PackingRules.Exact)]
    public enum ShaderOptions
    {
        /// <summary>Supports colored shadows in shaders.</summary>
        ColoredShadow = 1,
        /// <summary>Uses [camera-relative rendering](../manual/Camera-Relative-Rendering.md) to enhance precision.</summary>
        CameraRelativeRendering = 1,
        /// <summary>Uses pre-exposition to enhance color precision.</summary>
        PreExposition = 1,
        /// <summary>Precomputes atmospheric attenuation for the directional light on the CPU. This makes it independent from the fragment's position, which increases performance but reduces accuracy.</summary>
        PrecomputedAtmosphericAttenuation = 0,

        /// <summary>Maximum number of views for XR.</summary>
#if ENABLE_VR
        XrMaxViews = 2,
#else
        XrMaxViews = 1,
#endif

        /// <summary>Support for area lights.</summary>
        AreaLights = 1,

        /// <summary>Support for barn doors.</summary>
        BarnDoor = 0
    };

    // Note: #define can't be use in include file in C# so we chose this way to configure both C# and hlsl
    // Changing a value in this enum Config here require to regenerate the hlsl include and recompile C# and shaders
    /// <summary>
    /// Project-wide shader configuration options.
    /// <remarks>This class reflects the enum. Use it in C# code to check the current configuration.</remarks>
    /// </summary>
    public class ShaderConfig
    {
        // REALLY IMPORTANT! This needs to be the maximum possible XrMaxViews for any supported platform!
        // this needs to be constant and not vary like XrMaxViews does as it is used to generate the cbuffer declarations
        /// <summary>Maximum number of XR views for constant buffer allocation.</summary>
        public const int k_XRMaxViewsForCBuffer = 2;

        /// <summary>Indicates whether to use [camera-relative rendering](../manual/Camera-Relative-Rendering.md) to enhance precision.</summary>
        ///<seealso cref="ShaderOptions.CameraRelativeRendering"/>
        public static int s_CameraRelativeRendering = (int)ShaderOptions.CameraRelativeRendering;
        /// <summary>Indicates whether to use pre-exposition to enhance color prevision.</summary>
        ///<seealso cref="ShaderOptions.PreExposition"/>
        public static int s_PreExposition = (int)ShaderOptions.PreExposition;
        /// <summary>Specifies the maximum number of views to use for XR rendering.</summary>
        ///<seealso cref="ShaderOptions.XrMaxViews"/>
        public static int s_XrMaxViews = (int)ShaderOptions.XrMaxViews;
        /// <summary>Indicates whether to precompute atmosphere attenuation for the directional light on the CPU.</summary>
        ///<seealso cref="ShaderOptions.PrecomputedAtmosphericAttenuation"/>
        public static int s_PrecomputedAtmosphericAttenuation = (int)ShaderOptions.PrecomputedAtmosphericAttenuation;

        /// <summary>Indicates whether to support area lights.</summary>
        ///<seealso cref="ShaderOptions.AreaLights"/>
        public static int s_AreaLights = (int)ShaderOptions.AreaLights;
        /// <summary>Indicates whether to support barn doors.</summary>
        ///<seealso cref="ShaderOptions.BarnDoor"/>
        public static int s_BarnDoor = (int)ShaderOptions.BarnDoor;
    }
}
