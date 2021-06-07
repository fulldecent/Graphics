using System;
using System.Linq;

namespace UnityEngine.Rendering
{
    /// <summary>
    /// This attribute allows you to add information for a class to be supported on a render pipeline
    /// </summary>
    [AttributeUsage(AttributeTargets.Class)]
    public sealed class SupportedOnAttribute : Attribute
    {
        /// <summary>
        /// The list of pipeline types that the target class supports
        /// </summary>
        public Type[] pipelineTypes { get; }

        /// <summary>
        /// Creates a new <seealso cref="SupportedOnAttribute"/> instance.
        /// </summary>
        /// <param name="pipelineTypes">The list of pipeline types that the target class supports</param>
        public SupportedOnAttribute(params Type[] pipelineTypes)
        {
            if (pipelineTypes == null)
                throw new Exception($"Specify a list of supported pipeline");

            // Make sure that we only allow the class types that inherit from the render pipeline
            foreach (var t in pipelineTypes)
            {
                if (!typeof(RenderPipeline).IsAssignableFrom(t))
                    throw new Exception(
                        $"You can only specify types that inherit from {typeof(RenderPipeline)}, please check {t}");
            }

            this.pipelineTypes = pipelineTypes;
        }
    }

    /// <summary>
    /// Attribute used to customize UI display.
    /// </summary>
    [AttributeUsage(AttributeTargets.Field)]
    public class DisplayInfoAttribute : Attribute
    {
        /// <summary>Display name used in UI.</summary>
        public string name;
        /// <summary>Display order used in UI.</summary>
        public int order;
    }

    /// <summary>
    /// Attribute used to customize UI display to allow properties only be visible when "Show Additional Properties" is selected
    /// </summary>
    [AttributeUsage(AttributeTargets.Field)]
    public class AdditionalPropertyAttribute : Attribute
    {
    }
}
