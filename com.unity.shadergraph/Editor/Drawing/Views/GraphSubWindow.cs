using System.Collections.Generic;
using UnityEditor.Experimental.GraphView;
using UnityEngine;
using UnityEngine.UIElements;

namespace UnityEditor.ShaderGraph.Drawing.Views
{
    class GraphSubWindow : GraphElement, IResizable
    {
        Dragger m_Dragger;

        // This needs to be something that each subclass defines for itself at creation time
        // if they all use the same they'll be stacked on top of each other at SG window creation
        protected WindowDockingLayout windowDockingLayout { get; private set; } = new WindowDockingLayout
        {
            dockingTop = true,
            dockingLeft = false,
            verticalOffset = 8,
            horizontalOffset = 8,
        };

        protected VisualElement m_MainContainer;
        protected VisualElement m_Root;
        protected Label m_TitleLabel;
        protected Label m_SubTitleLabel;
        protected ScrollView m_ScrollView;
        protected VisualElement m_ContentContainer;
        protected VisualElement m_HeaderItem;
        protected GraphView m_GraphView;

        // These are used as default values for styling and layout purposes
        // They can be overriden if a child class wants to roll its own style and layout behavior
        public virtual string layoutKey => "UnityEditor.ShaderGraph.SubWindow";
        public virtual string styleName => "GraphSubWindow";
        public virtual string UxmlName => "GraphSubWindow";

        // Each sub-window will override these if they need to
        public virtual string elementName => "";
        public virtual string windowTitle => "";

        public GraphView graphView
        {
            get
            {
                if (!isWindowed && m_GraphView == null)
                    m_GraphView = GetFirstAncestorOfType<GraphView>();
                return m_GraphView;
            }

            set
            {
                if (!isWindowed)
                    return;
                m_GraphView = value;
            }
        }

        public List<ISelectable> selection => graphView?.selection;

        public override string title
        {
            get { return m_TitleLabel.text; }
            set { m_TitleLabel.text = value; }
        }

        public string subTitle
        {
            get { return m_SubTitleLabel.text; }
            set { m_SubTitleLabel.text = value; }
        }

        // Intended for future handling of docking to sides of the shader graph window
        bool m_IsWindowed;
        public bool isWindowed
        {
            get { return m_IsWindowed; }
            set
            {
                if (m_IsWindowed == value) return;

                if (value)
                {
                    capabilities &= ~Capabilities.Movable;
                    AddToClassList("windowed");
                    this.RemoveManipulator(m_Dragger);
                }
                else
                {
                    capabilities |= Capabilities.Movable;
                    RemoveFromClassList("windowed");
                    this.AddManipulator(m_Dragger);
                }
                m_IsWindowed = value;
            }
        }

        public override VisualElement contentContainer => m_ContentContainer;

        private bool m_IsResizable = false;

        // Can be set by child classes as needed
        protected bool isWindowResizable
        {
            get => m_IsResizable;
            set
            {
                if (m_IsResizable != value)
                {
                    m_IsResizable = value;
                    HandleResizingBehavior(m_IsResizable);
                }
            }
        }

        void HandleResizingBehavior(bool isResizable)
        {
            if (isResizable)
            {
                var resizeElement = this.Q<ResizableElement>();
                resizeElement.BindOnResizeCallback(OnWindowResize);
                hierarchy.Add(resizeElement);
            }
            else
            {
                var resizeElement = this.Q<ResizableElement>();
                resizeElement.SetResizeRules(ResizableElement.Resizer.None);
                hierarchy.Remove(resizeElement);
            }
        }

        protected void SetResizingRules(ResizableElement.Resizer resizeDirections)
        {
            var resizeElement = this.Q<ResizableElement>();
            resizeElement.SetResizeRules(resizeDirections);
        }

        private bool m_IsScrollable = false;

        // Can be set by child classes as needed
        protected bool isWindowScrollable
        {
            get => m_IsScrollable;
            set
            {
                if (m_IsScrollable != value)
                {
                    m_IsScrollable = value;
                    HandleScrollingBehavior(m_IsScrollable);
                }
            }
        }

        void HandleScrollingBehavior(bool scrollable)
        {
            if (scrollable)
            {
                // Remove the sections container from the content item and add it to the scrollview
                m_ContentContainer.RemoveFromHierarchy();
                m_ScrollView.Add(m_ContentContainer);
                AddToClassList("scrollable");
            }
            else
            {
                // Remove the sections container from the scrollview and add it to the content item
                m_ContentContainer.RemoveFromHierarchy();
                m_Root.Add(m_ContentContainer);

                RemoveFromClassList("scrollable");
            }
        }

        protected GraphSubWindow(GraphView associatedGraphView) : base()
        {
            m_GraphView = associatedGraphView;
            m_GraphView.Add(this);

            var styleSheet = Resources.Load<StyleSheet>($"Styles/{styleName}");
            // Setup VisualElement from Stylesheet and UXML file
            styleSheets.Add(styleSheet);
            var uxml = Resources.Load<VisualTreeAsset>($"UXML/{UxmlName}");
            m_MainContainer = uxml.Instantiate();
            m_MainContainer.AddToClassList("mainContainer");

            m_Root = m_MainContainer.Q("content");
            m_HeaderItem = m_MainContainer.Q("header");
            m_HeaderItem.AddToClassList("subWindowHeader");
            m_ScrollView = m_MainContainer.Q<ScrollView>("scrollView");
            m_TitleLabel = m_MainContainer.Q<Label>(name: "titleLabel");
            m_SubTitleLabel = m_MainContainer.Q<Label>(name: "subTitleLabel");
            m_ContentContainer = m_MainContainer.Q(name: "contentContainer");

            hierarchy.Add(m_MainContainer);

            capabilities |= Capabilities.Movable | Capabilities.Resizable;
            style.overflow = Overflow.Hidden;
            focusable = false;

            name = elementName;
            title = windowTitle;

            ClearClassList();
            AddToClassList(name);

            BuildManipulators();

            /* Event interception to prevent GraphView manipulators from being triggered */
            RegisterCallback<DragUpdatedEvent>(e =>
            {
                e.StopPropagation();
            });

            // prevent Zoomer manipulator
            RegisterCallback<WheelEvent>(e =>
            {
                e.StopPropagation();
            });

            RegisterCallback<MouseDownEvent>(e =>
            {
                // prevent ContentDragger manipulator
                e.StopPropagation();
            });
        }

        protected void ShowWindow()
        {
            this.style.visibility = Visibility.Visible;
            contentContainer.MarkDirtyRepaint();
        }

        protected void HideWindow()
        {
            this.style.visibility = Visibility.Hidden;
            #if UNITY_2021_1_OR_NEWER
            this.m_ScrollView.verticalScrollerVisibility = ScrollerVisibility.Hidden;
            this.m_ScrollView.horizontalScrollerVisibility = ScrollerVisibility.Hidden;
            #else
            this.m_ScrollView.showVertical = false;
            this.m_ScrollView.showHorizontal = false;
            #endif

            contentContainer.Clear();
            contentContainer.MarkDirtyRepaint();
        }

        void BuildManipulators()
        {
            m_Dragger = new Dragger { clampToParentEdges = true };
            RegisterCallback<MouseUpEvent>(OnMoved);
            this.AddManipulator(m_Dragger);
        }

        #region Layout
        public void ClampToParentLayout(Rect parentLayout)
        {
            windowDockingLayout.CalculateDockingCornerAndOffset(layout, parentLayout);
            windowDockingLayout.ClampToParentWindow();
            windowDockingLayout.ApplyPosition(this);
            SerializeLayout();
        }

        public void OnStartResize()
        {
        }

        public void OnResized()
        {
            windowDockingLayout.size = layout.size;
            SerializeLayout();
        }

        public void DeserializeLayout()
        {
            var serializedLayout = EditorUserSettings.GetConfigValue(layoutKey);
            if (!string.IsNullOrEmpty(serializedLayout))
                windowDockingLayout = JsonUtility.FromJson<WindowDockingLayout>(serializedLayout);
            else
            {
                // The window size needs to come from the stylesheet or UXML as opposed to being defined in code
                windowDockingLayout.size = layout.size;
            }

            windowDockingLayout.ApplySize(this);
            windowDockingLayout.ApplyPosition(this);
        }

        protected void AddStyleSheetFromPath(string styleSheetPath)
        {
            StyleSheet sheetAsset = Resources.Load<StyleSheet>(styleSheetPath);;

            if (sheetAsset == null)
            {
                Debug.LogWarning(string.Format("Style sheet not found for path \"{0}\"", styleSheetPath));
                return;
            }
            styleSheets.Add(sheetAsset);
        }

        void SerializeLayout()
        {
            windowDockingLayout.size = layout.size;
            var serializedLayout = JsonUtility.ToJson(windowDockingLayout);
            EditorUserSettings.SetConfigValue(layoutKey, serializedLayout);
        }

        void OnMoved(MouseUpEvent upEvent)
        {
            windowDockingLayout.CalculateDockingCornerAndOffset(layout, graphView.layout);
            windowDockingLayout.ClampToParentWindow();

            SerializeLayout();
        }

        void OnWindowResize(MouseUpEvent upEvent)
        {

        }
    }
    #endregion
}
