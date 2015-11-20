/**
 * Agent Development Environment (ADE)
 *
 * @version 1.0
 * @author Matthias Scheutz
 * 
 * Copyright 1997-2013 Matthias Scheutz
 * All rights reserved. Do not copy and use without permission.
 * For questions contact Matthias Scheutz at mscheutz@gmail.com
 */
package ade.gui;

import java.awt.Component;
import java.awt.Container;
import java.awt.Dimension;
import java.awt.Insets;
import java.awt.Point;
import java.awt.Rectangle;
import java.awt.Toolkit;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.ComponentAdapter;
import java.awt.event.ComponentEvent;
import java.awt.event.WindowEvent;

import javax.swing.JDesktopPane;
import javax.swing.JFrame;
import javax.swing.JInternalFrame;
import javax.swing.JPanel;
import javax.swing.SwingUtilities;
import javax.swing.Timer;
import javax.swing.event.InternalFrameEvent;

/**
 * A class that must be extended by any visualization that wants to be
 * accessible from the GUI. It in turn inherits from JPanel, and provides
 * convenience methods for "free" (along with enforcing methods that are
 * declared abstract, and thus MUST be overridden). The ADEGuiPanel is intended
 * to reside within an ADEGuiInnerFrame (a JInnerFrame upon the JDesktopPane of
 * the ADEGuiComponentImpl, aka the ADESystemContainer), or within an
 * ADEGuiExternalFrame. The timing of how often the GUI refreshes is controlled
 * by the topmost ADEGuiExternalFrame, e.g., either by the JFrame itself (for
 * external visualizations), or by the external JFrame of the ADEsystemView.
 *
 * @author mzlatkov
 */
public abstract class ADEGuiPanel extends JPanel {

    private static final long serialVersionUID = 1L;
    private ADEGuiCallHelper myGUICallHelper;
    private String myComponentName;
    private String myTitle;
    private Timer myTimer; // timer for updating the GUI (each panel has its
    //     own timer, so that it can control its own refresh rate)
    private VisibilityDeterminer visibilityDeterminer;

    ////////////////////////////////////////////////////
    // METHODS THAT MUST BE IMPLEMENTED BY SUBCLASSES:
    ////////////////////////////////////////////////////
    /**
     * The main visualization method, which will be called time and time again.
     * It will also be called upon resizing the frame (or whenever else public
     * void paint(Graphics g) is called. NOTE that if you require a Graphics
     * object for the visualization, you can simply get it by calling
     * this.getGraphics(). Then you can do the usual Graphics-y things
     * (g.drawRect(0,0,100,100)), etc.
     */
    public abstract void refreshGui();

    ////////////////////////////////////////////////////
    // METHODS THAT YOU MIGHT WANT TO OVERRIDE:
    ////////////////////////////////////////////////////
    /**
     * get initial size. by default, just the preferred size of the panel That
     * said, sometimes the panel does not know how to determine its own
     * preferred size well, or the initial size might be set to something
     * entirely different. If so, getInitSize(boolean isInternalWindow) or
     * getPreferredSize() or possibly both should definitely be overwritten. If
     * you want to distinguish between an initial size for a big-window GUI
     * versus as an internal frame inside the ADE SystemView, you should
     * likewise override this method.
     *
     * @param isInternalWindow
     */
    public Dimension getInitSize(boolean isInternalWindow) {
        Dimension minSize = this.getPreferredSize();
        return new Dimension(Math.max(20, minSize.width),
                Math.max(20, minSize.height));
    }

    /**
     * Initial title. By default, just the component name. If you want anything
     * else, override it! You can also, at any time, call setTitle(String) to
     * update the title while the visualization is running
     *
     * @return
     */
    public String getInitTitle() {
        return myComponentName;
    }

    /**
     * Notifies the GUI the first time that the GUI is shown on screen (and so
     * hence now it has dimensions, for instance, if case you're doing some
     * clever sizing). Also lets you react to whether or not the GUI is a frame
     * by itself or part of the ADESystemView, if that makes any difference to
     * you.
     */
    public void isLoadedCallback(boolean isInternalWindow) {
        // do nothing in the super-class, this is only for the benefit of 
        //    sub-classes that want to override this.
    }

    //////////////////////////////////////////////////////
    // METHODS PROVIDED BY THE abstract ADEGuiPanel CLASS:
    //////////////////////////////////////////////////////
    /**
     * the main ADEGUI constructor: For details on how to create ADEGUI
     * visualizations, see
     * http://hri.cogs.indiana.edu/hrilab/index.php/Writing_GUI_Visualizers.
     *
     * @param guiCallHelper: a call helper that is generated by ADERegistryImpl
     * for visualizations internal to the ADE SystemView visualization, or by
     * ADEComponentImpl for external frames (obtained via a -g/--GUI flag). In the
     * case of all classes but the actual ADEGuiPanel, just pass along the
     * ADEGuiCallHelper along to the super constructor.
     * @param refreshRate: each visualization should determine how often it
     * should be refreshed (in milliseconds). For visualizations that change
     * often, e.g., ADESim, a refresh rate of 100ms, e.g., 10x/sec might be
     * necessary; other visualizations might do just fine with 500 or even 1000
     * ms.
     */
    public ADEGuiPanel(ADEGuiCallHelper guiCallHelper, int refreshRate) {
        super();

        this.setFocusable(true); // that way, will be able to capture key strokes, etc

        this.myGUICallHelper = guiCallHelper;

        // The abstract GUI Panel needs to know the name of the component to set
        //     an initial title; and, chances are, the visualization implementation
        //     might also want to get this information (obtainable through getComponentName())
        try {
            this.myComponentName = (String) callComponent("getName");
        } catch (Exception e) {
            this.myComponentName = "[Unknown component name]";
        }

        if (refreshRate < 0) {
            throw new NumberFormatException("GUI Refresh rate cannot be negative!");
        }

        this.myTimer = new Timer(refreshRate, new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                refreshGuiIfVisible();
            }
        });
        this.myTimer.start();
    }

    private void refreshGuiIfVisible() {
        if (this.visibilityDeterminer == null) {
            return;
        } else {
            if (visibilityDeterminer.isVisible()) {
                this.refreshGui();
            }
        }
    }

    public final void isLoaded(boolean isInternalWindow) {
        // notify the actual sub-class, if IT were overriding anything:
        this.isLoadedCallback(isInternalWindow);

        // then refresh its own gui
        this.refreshGui();
    }

    /**
     * A very helpful method for creating OTHER windows (dialogs, wizards, etc),
     * for your GUI visualization. This is necessary because if your dialog was
     * a JFrame, it may work fine for JFrame GUIs, but would look downright
     * awkward (and have focus issues) when run via the ADEGui -- and
     * vice-versa. Moreover, this method will take care of placing your window
     * in a visually-appealing spot next to your "main" window, and make sure it
     * doesn't run offscreen, etc.
     *
     * @param instigatingADEGuiPanel: your "main" visualization that you know
     * and love
     * @param newHelperPanel: the panel for your new dialog/wizard/etc. Note
     * that if anywhere in your code you call .setVisible(false), this will be
     * equivalent to a window-closing call (useful for "ok" and "cancel"
     * buttons).
     * @param initialSize: initial size for the panel (insets will be taken care
     * of for you)
     * @param centerOnParent. if true, will try to center around parent; if
     * false, will put the window as far as possible to the right of the parent,
     * without going off bounds.
     * @param resizable: yes or no.
     * @param title: title for the window
     * @param defaultCloseOperation: close operation:
     * WindowConstants.DISPOSE_ON_CLOSE, WindowConstants.DO_NOTHING_ON_CLOSE,
     * etc.
     */
    public final Container createWindowForHelperPanel(
            JPanel newHelperPanel, Dimension initialSize, boolean centerOnParent,
            boolean resizable, String title,
            int defaultCloseOperation) {

        Container parent = this.findParentFrame();

        if (parent instanceof JFrame) {
            final JFrame newFrame = new JFrame(title);
            newFrame.setContentPane(newHelperPanel);
            newFrame.setResizable(resizable);
            newFrame.setDefaultCloseOperation(defaultCloseOperation);
            newFrame.setVisible(true);

            // if panel is set to false visiblity, just automate the window closing action
            newHelperPanel.addComponentListener(new ComponentAdapter() {
                @Override
                public void componentHidden(ComponentEvent e) {
                    Toolkit.getDefaultToolkit().getSystemEventQueue().postEvent(
                            new WindowEvent(newFrame, WindowEvent.WINDOW_CLOSING));
                }
            });

            // set size and position only after setting visible, otherwise insets (and other things
            //    don't work)
            newFrame.setSize(getSizeWithInsets(initialSize, newFrame.getInsets()));
            helperPanelSetLocation(newFrame, parent, centerOnParent,
                    Toolkit.getDefaultToolkit().getScreenSize());

            return newFrame;

        } else if (parent instanceof JInternalFrame) {
            JDesktopPane mainGUIPanel = (JDesktopPane) SwingUtilities.getAncestorOfClass(JDesktopPane.class, parent);
            final JInternalFrame newFrame = new JInternalFrame(title);
            newFrame.setContentPane(newHelperPanel);
            newFrame.setResizable(resizable);
            newFrame.setDefaultCloseOperation(defaultCloseOperation);

            // a few extra parameters for internal frames:
            newFrame.setClosable(true);
            newFrame.setMaximizable(true);
            newFrame.setIconifiable(true);

            newFrame.setVisible(true);
            mainGUIPanel.add(newFrame);

            // if panel is set to false visiblity, just automate the window closing action
            newHelperPanel.addComponentListener(new ComponentAdapter() {
                @Override
                public void componentHidden(ComponentEvent e) {
                    Toolkit.getDefaultToolkit().getSystemEventQueue().postEvent(
                            new InternalFrameEvent(newFrame, InternalFrameEvent.INTERNAL_FRAME_CLOSING));
                }
            });

            // set size and position only after setting visible, otherwise insets (and other things
            //    don't work)
            newFrame.setSize(getSizeWithInsets(initialSize, newFrame.getInsets()));
            helperPanelSetLocation(newFrame, parent, centerOnParent, mainGUIPanel.getSize());

            // tell the desktop manager to bring the frame to front (otherwise it will
            //    be lost behind the active frame, defeating the point of bringing it up!)
            mainGUIPanel.getDesktopManager().activateFrame(newFrame);

            return newFrame;

        } else {
            System.err.println("Could not created ADEGuiPanel for \"" + title + "\"");
            return null;
        }
    }

    private static final void helperPanelSetLocation(Component newFrame,
            Container parent, boolean centerOnParent, Dimension containerSize) {

        // on initial setVisible, move wizard to a good location next to the visualization
        Rectangle visBounds = parent.getBounds();
        Point possibleLocation;

        if (centerOnParent) {
            possibleLocation = new Point(
                    (int) (visBounds.x + (visBounds.getWidth() - newFrame.getWidth()) / 2),
                    (int) (visBounds.y + (visBounds.getHeight() - newFrame.getHeight()) / 2));
        } else {
            possibleLocation = new Point(visBounds.x + visBounds.width, visBounds.y);
        }

        // make sure not too far right
        if ((possibleLocation.x + newFrame.getWidth()) > containerSize.width) {
            possibleLocation = new Point(containerSize.width - newFrame.getWidth(), possibleLocation.y);
        }
        // but make sure didn't go into negatives (too far left), either:
        if (possibleLocation.x < 0) {
            possibleLocation = new Point(0, possibleLocation.y);
        }


        // now make sure that not too far on the bottom:
        if ((possibleLocation.y + newFrame.getHeight()) > containerSize.height) {
            possibleLocation = new Point(possibleLocation.x, containerSize.height - newFrame.getHeight());
        }
        // but not too far!  don't let y get below 0:
        if (possibleLocation.y < 0) {
            possibleLocation = new Point(possibleLocation.x, 0);
        }


        // finally set it:
        newFrame.setLocation(possibleLocation);
    }

    public static final Dimension getSizeWithInsets(Dimension innerSize, Insets insets) {
        return new Dimension(innerSize.width + insets.left + insets.right,
                innerSize.height + insets.top + insets.bottom);
    }

    /**
     * public method that will call a specified method on a component (public so
     * that those objects that have a reference to the visualization -- such as
     * a key listener -- can ask the visualization to, in turn, dispatch
     * instructions to the underlying component)
     *
     * @param methodName
     * @param args
     * @return
     * @throws Exception
     */
    public final Object callComponent(String methodName, Object... args) throws Exception {
        return myGUICallHelper.call(methodName, args);
    }

    /**
     * A method by which ADEGuiPanels can set the frame's title, even though
     * panels in their own right are not allowed to set titles
     *
     * @param titleToSetTo
     */
    public final void setTitle(String titleToSetTo) {
        myTitle = titleToSetTo;

        Container parent = findParentFrame();
        if (parent instanceof JFrame) {
            ((JFrame) parent).setTitle(myTitle);
        } else if (parent instanceof JInternalFrame) {
            ((JInternalFrame) parent).setTitle(myTitle);
        }
        // if parent is null, that just means that got called from constructor, before frame is set.
        //     once frame is created, it will call getTitle, so it's no problem.
    }

    public final Container findParentFrame() {
        Container parent = this.getParent();
        // try to set it now, if parent is not null.
        while (parent != null) {
            if ((parent instanceof JFrame) || (parent instanceof JInternalFrame)) {
                return parent;
            } else {
                // keep iterating up and up!
                parent = parent.getParent();
            }
        }

        // if hasn't quit with parent: (should never happen, I don't think...)
        return null;
    }

    public final String getTitle() {
        return myTitle;
    }

    /**
     * A method by which ADEGuiPanels can dispose their own visualization window
     */
    public final void disposeVisualization() {
        Container parent = findParentFrame();
        // try to set it now, if parent is not null.
        if (parent instanceof JFrame) {
            ((JFrame) parent).dispose();
        } else if (parent instanceof JInternalFrame) {
            ((JInternalFrame) parent).dispose();
        } else {
            // the only time when parent is not either jframe or jinternal frame
            //     is if it is null (during time of creation, before being assigned
            //     a frame.  So just throw an exception, let the constructor
            //     for the panel choke on it, and in so doing prevent the frame 
            //     from ever being created!
            throw new Error("Requesting visualization disposal");
        }
    }

    public String getComponentName() {
        return myComponentName;
    }

    void setVisibilityDeterminer(
            VisibilityDeterminer visibilityDeterminer) {
        this.visibilityDeterminer = visibilityDeterminer;
    }

    /**
     * an interface that ADEGuiExternalFrame and ADEGuiInternalFrame create and
     * pass to the setVisiblityDeterminer method, wherein they can check if the
     * frame is visible, not iconified (e.g., minimized), etc -- information
     * that the panel itself cannot know anything about. That way, the panel
     * does not waste network traffic trying in trying to visualize items while
     * minimized.
     */
    interface VisibilityDeterminer {

        public boolean isVisible();
    }
}