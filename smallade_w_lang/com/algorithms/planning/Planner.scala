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
package com.algorithms.planning

import scala.concurrent.{ExecutionContext, Future, future}

import ExecutionContext.Implicits.global

abstract class Planner[T] {
  def getStates: StateContainer[T]
  def plan: Option[Path[T]]
  def startPlanning: Future[Option[Path[T]]] = future {plan}
}
