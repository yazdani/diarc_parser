/**
 * Agent Development Environment (ADE)
 *
 * @version 1.0
 * @author M@
 *
 * Copyright 1997-2013 M@ Dunlap and HRILab (hrilab.org)
 * All rights reserved. Do not copy and use without permission.
 * For questions contact M@ at <matthew.dunlap+hrilab@gmail.com>
 */
package utilities.ui.graph;

import ade.gui.ADEGuiCallHelper;
import ade.gui.ADEGuiPanel;
import java.awt.Color;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;

/**
 *
 * @author M@ <matthew.dunlap+hrilab@gmail.com>
 */
public class GraphViewer extends ADEGuiPanel {
  // TODO: expose these in the API
  int xIndex = 21;
  int yIndex = 22;
  Map<Integer, double[]> vertices = null;
  Map<Integer, Set<Integer>> edges = null;
  double[] rangeMins = null;
  double[] rangeMaxs = null;

  /** Creates new form CanvasPlayground */
  public GraphViewer(ADEGuiCallHelper helper, Map<Integer, double[]> vertices, Map<Integer, Set<Integer>> edges, int xDimIndex, int yDimIndex) {
    super(helper, 100);
    initComponents();
    canvas1.setForeground(Color.black);
    xIndex = xDimIndex;
    yIndex = yDimIndex;

    this.vertices = vertices;
    this.edges = edges;
  }

  public GraphViewer(ADEGuiCallHelper helper, Map<Integer, double[]> vertices, Map<Integer, Set<Integer>> edges, double[] rangeMins, double[] rangeMaxs, int xDimIndex, int yDimIndex) {
    super(helper, 100);
    initComponents();
    canvas1.setForeground(Color.black);
    xIndex = xDimIndex;
    yIndex = yDimIndex;

    this.vertices = vertices;
    this.edges = edges;
    this.rangeMins = new double[rangeMins.length];
    this.rangeMaxs = new double[rangeMaxs.length];
    for (int i = 0; i < rangeMins.length; i++) {
      this.rangeMins[i] = rangeMins[i];
      this.rangeMaxs[i] = rangeMaxs[i];
    }
  }

  /** This method is called from within the constructor to
   * initialize the form.
   * WARNING: Do NOT modify this code. The content of this method is
   * always regenerated by the Form Editor.
   */
  @SuppressWarnings("unchecked")
  // <editor-fold defaultstate="collapsed" desc="Generated Code">//GEN-BEGIN:initComponents
  private void initComponents() {

    canvas1 = new java.awt.Canvas();

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
    for (Entry<Integer, double[]> entry : vertices.entrySet()) {
      double origX = project(entry.getValue(), xIndex, canvas1.getWidth());
      double origY = project(entry.getValue(), yIndex, canvas1.getHeight());
      canvas1.getGraphics().drawRect((int) origX, (int) origY, 2, 2);
      if (edges.containsKey(entry.getKey())) {
        for (int edge : edges.get(entry.getKey())) {
          double destX = project(vertices.get(edge), xIndex, canvas1.getWidth());
          double destY = project(vertices.get(edge), yIndex, canvas1.getHeight());

          canvas1.getGraphics().drawLine((int) origX, (int) origY, (int) destX, (int) destY);
        }
      }
    }
  }

  double project(double[] collection, int i, double dim) {
    if (rangeMins == null) {
      return collection[i] * dim;
    }
    return (collection[i] - rangeMins[i]) / (rangeMaxs[i] - rangeMins[i]) * dim;
  }
}