/**
 * ADE 1.0
 * Copyright 1997-2010 HRILab (http://hrilab.org/)
 *
 * All rights reserved.  Do not copy and use without permission.
 * For questions contact Matthias Scheutz at mscheutz@indiana.edu
 * Last update: April 2012
 * 
 * LRFComponent.java
 *
 * @author Paul Schermerhorn
 */
package com.lrf;

import ade.*;
import com.interfaces.*;
import java.rmi.*;
import com.lrf.polar_laser_scan;

/**
 * Base class for LRF servers.
 */
public interface LRFComponent extends ADEComponent, LaserComponent {
    public polar_laser_scan getPolarScanData() throws RemoteException;
}

