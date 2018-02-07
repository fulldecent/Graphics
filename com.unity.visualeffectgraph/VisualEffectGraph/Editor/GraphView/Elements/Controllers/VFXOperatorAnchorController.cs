using UnityEditor.Experimental.UIElements.GraphView;
using UnityEngine;
using System.Collections.Generic;
using System.Linq;
using System;

namespace UnityEditor.VFX.UI
{
    abstract class VFXOperatorAnchorController : VFXDataAnchorController
    {
        public VFXOperatorAnchorController(VFXSlot model, VFXSlotContainerController sourceNode, bool hidden) : base(model, sourceNode, hidden)
        {
        }

        public static System.Type GetDisplayAnchorType(VFXSlot slot)
        {
            System.Type newAnchorType = null;

            if (slot.property.type == typeof(FloatN))
            {
                newAnchorType = VFXTypeUtility.GetFloatTypeFromComponentCount(VFXTypeUtility.GetComponentCount(slot.refSlot));
                if (newAnchorType == null)
                    newAnchorType = typeof(FloatN);
            }
            else
                newAnchorType = slot.property.type;

            return newAnchorType;
        }

        public override void UpdateInfos()
        {
            if (model.direction == VFXSlot.Direction.kInput)
            {
                System.Type newAnchorType = GetDisplayAnchorType(model);

                if (newAnchorType != portType)
                {
                    portType = newAnchorType;
                }
            }
            else
                base.UpdateInfos();
        }
    }


    class VFXInputOperatorAnchorController : VFXOperatorAnchorController
    {
        public VFXInputOperatorAnchorController(VFXSlot model, VFXSlotContainerController sourceNode, bool hidden) : base(model, sourceNode, hidden)
        {
        }

        public override Direction direction
        {
            get
            {
                return Direction.Input;
            }
        }
    }

    class VFXOutputOperatorAnchorController : VFXOperatorAnchorController
    {
        public VFXOutputOperatorAnchorController(VFXSlot model, VFXSlotContainerController sourceNode, bool hidden) : base(model, sourceNode, hidden)
        {
        }

        public override Direction direction
        {
            get
            {
                return Direction.Output;
            }
        }
    }
}
