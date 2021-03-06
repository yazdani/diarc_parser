/*
 * Agent Development Environment (ADE)
 *
 * @version 1.0
 * @author M@
 *
 * Copyright 1997-2013 M@ Dunlap and HRILab (hrilab.org)
 * All rights reserved. Do not copy and use without permission.
 * For questions contact M@ at <matthew.dunlap+hrilab@gmail.com>
 */
package utilities.ui.scratchpads;

import ade.gui.ADEGuiCallHelper;
import ade.gui.ADEGuiPanel;

import java.awt.*;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;

/**
 *
 * @author M@ <matthew.dunlap+hrilab@gmail.com>
 */
public class CanvasPlayground extends ADEGuiPanel {
  /** Creates new form CanvasPlayground */
  public CanvasPlayground(ADEGuiCallHelper helper) {
    super(helper, 10000);
    initComponents();
  }

  /** This method is called from within the constructor to
   * initialize the form.
   * WARNING: Do NOT modify this code. The content of this method is
   * always regenerated by the Form Editor.
   */
  @SuppressWarnings("unchecked")
  // <editor-fold defaultstate="collapsed" desc="Generated Code">//GEN-BEGIN:initComponents
  private void initComponents() {
    canvas1 = new CanvasPlaygroundCanvas();

    javax.swing.GroupLayout layout = new javax.swing.GroupLayout(this);
    this.setLayout(layout);
    layout.setHorizontalGroup(
      layout.createParallelGroup(javax.swing.GroupLayout.Alignment.LEADING)
      .addComponent(canvas1, javax.swing.GroupLayout.DEFAULT_SIZE, 400, Short.MAX_VALUE)
    );
    layout.setVerticalGroup(
      layout.createParallelGroup(javax.swing.GroupLayout.Alignment.LEADING)
      .addComponent(canvas1, javax.swing.GroupLayout.DEFAULT_SIZE, 300, Short.MAX_VALUE)
    );
  }// </editor-fold>//GEN-END:initComponents
  // Variables declaration - do not modify//GEN-BEGIN:variables
  private java.awt.Canvas canvas1;
  // End of variables declaration//GEN-END:variables

  @Override
  public void refreshGui() {
    canvas1.repaint();
  }
}
