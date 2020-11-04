// *** WARNING: this file was generated by test. ***
// *** Do not edit by hand unless you're certain you know what you are doing! ***

using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Threading.Tasks;
using Pulumi.Serialization;

namespace Pulumi.PlantProvider.Outputs
{

    [OutputType]
    public sealed class Container
    {
        public readonly Pulumi.PlantProvider.ContainerBrightness? Brightness;
        public readonly string? Color;
        public readonly string? Material;
        public readonly Pulumi.PlantProvider.ContainerSize Size;

        [OutputConstructor]
        private Container(
            Pulumi.PlantProvider.ContainerBrightness? brightness,

            string? color,

            string? material,

            Pulumi.PlantProvider.ContainerSize size)
        {
            Brightness = brightness;
            Color = color;
            Material = material;
            Size = size;
        }
    }
}
