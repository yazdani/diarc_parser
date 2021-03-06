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
package utilities.ui.frequency;

import ade.gui.ADEGuiCallHelper;
import ade.gui.SuperADEGuiPanel;
import org.apache.commons.math3.stat.descriptive.DescriptiveStatistics;

/**
 * Displays the frequency at which you are calling tick on the provided counter.
 *
 * @author M@ <matthew.dunlap+hrilab@gmail.com>
 */
public class FrequencyMonitor extends SuperADEGuiPanel {
  long lastTime;
  DescriptiveStatistics stats;

  /**
   * Creates new form FrequencyMonitor
   */
  public FrequencyMonitor(ADEGuiCallHelper helper) {
    super(helper, 500);
    initComponents();
    outputLbl.setText("0 Hz");
    lastTime = System.currentTimeMillis();
    stats = new DescriptiveStatistics(1);

    this.setTitle(call("getDataName", String.class));
  }

  /**
   * Creates new form FrequencyMonitor
   */
  public FrequencyMonitor(ADEGuiCallHelper helper, int smoothingWindow) {
    super(helper, 500);
    initComponents();
    outputLbl.setText("0 Hz");
    lastTime = System.currentTimeMillis();
    stats = new DescriptiveStatistics(smoothingWindow);

    this.setTitle(call("getDataName", String.class));
}

  /**
   * This method is called from within the constructor to
   * initialize the form.
   * WARNING: Do NOT modify this code. The content of this method is
   * always regenerated by the Form Editor.
   */
  @SuppressWarnings("unchecked")
    // <editor-fold defaultstate="collapsed" desc="Generated Code">//GEN-BEGIN:initComponents
    private void initComponents() {

        outputLbl = new javax.swing.JLabel();

        outputLbl.setFont(new java.awt.Font("Dialog", 1, 36)); // NOI18N
        outputLbl.setHorizontalAlignment(javax.swing.SwingConstants.CENTER);
        outputLbl.setText("jLabel1");

        javax.swing.GroupLayout layout = new javax.swing.GroupLayout(this);
        this.setLayout(layout);
        layout.setHorizontalGroup(
            layout.createParallelGroup(javax.swing.GroupLayout.Alignment.LEADING)
            .addGroup(layout.createSequentialGroup()
                .addContainerGap()
                .addComponent(outputLbl, javax.swing.GroupLayout.DEFAULT_SIZE, 197, Short.MAX_VALUE)
                .addContainerGap())
        );
        layout.setVerticalGroup(
            layout.createParallelGroup(javax.swing.GroupLayout.Alignment.LEADING)
            .addGroup(layout.createSequentialGroup()
                .addContainerGap()
                .addComponent(outputLbl, javax.swing.GroupLayout.DEFAULT_SIZE, 132, Short.MAX_VALUE)
                .addContainerGap())
        );
    }// </editor-fold>//GEN-END:initComponents
    // Variables declaration - do not modify//GEN-BEGIN:variables
    private javax.swing.JLabel outputLbl;
    // End of variables declaration//GEN-END:variables

  @Override
  public void refreshGui() {
    int count = call("getCountAndReset", int.class);
    long nextTime = System.currentTimeMillis();
    long elapsed = nextTime - lastTime; // ms
    double frequency = 1000 * count / elapsed;
    lastTime = nextTime;
    stats.addValue(frequency);

    outputLbl.setText(String.format("%3.1f Hz", stats.getGeometricMean()));
  }
}
