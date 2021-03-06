comlink/actrclient.lisp.save                                                                        0000600 0000764 0000764 00000034062 10607015043 016757  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               ;;;*******************************************************************
;;;
;;; SWAGES
;;; Version 1.1
;;;
;;; (c) by Matthias Scheutz
;;;
;;; Rudimentary ACT-R Client (alpha)
;;;
;;; Last modified: 03-29-07
;;;
;;;******************************************************************* 

;;; for debugging: print out lots of comments
(defconstant verbose t)

;;; for logging standard output is connected to logger file, otherwise to /dev/null
(defconstant logging t)

;;; get the name of the standard error stream
#+:cmu
(defvar *standard-error* *error-output*)

#|
;;; either activate logging or redirect the output to /dev/null
(if logging
    (setq *standard-output* (open "/tmp/clientout" :direction :output :if-exists :overwrite :if-does-not-exist :create))
    ;;;(setq *standard-output* (open "/hafs2/kers7754/clientout" :direction :output :if-exists :overwrite :if-does-not-exist :create))
  (setq *standard-output* (open "/dev/null" :direction :output :if-exists :append)))

(if logging
    (setq *standard-error* (open "/tmp/clienterr" :direction :output :if-exists :overwrite :if-does-not-exist :create))
      ;;;(setq *standard-error* (open "/hafs2/kers7754/clienterr" :direction :output :if-exists :overwrite :if-does-not-exist :create))
  (setq *standard-error* (open "/dev/null" :direction :output :if-exists :append)))
|#

;;; load utility files for socket communication
(load "/home/mscheutz/palm/actr6/support/uni-files.lisp")

;;; USE these one for the cluster
;;;(load "/hafs2/kers7754/palm/actr6/support/uni-files.lisp")

;;; support for different lisp versions
;;; additional functions for sending items through a socket and flushing it
#+(or :openmcl :allegro)
(defun sendone (item socket)
   (prin1 item socket)
   (force-output socket))

#+:lispworks
(defun sendone (item socket)
  (prin1 item socket)
  #+:win32 (sleep .05)
  (finish-output socket))

#+:cmu
(defun sendone (item socket)
  (prin1 item socket)
  (finish-output socket))

#+:openmcl
(defun quitlisp ()
  (quit))

;;; the no-unwind statement is important, as the process will otherwise not quit
;;; STILL DOES NOT QUIT...
#+:allegro
(defun quitlisp ()
  (force-output *standard-output*)
  (close *standard-output*)
  (force-output *standard-error*)
  (close *standard-error*)
  (exit 0 :no-unwind t))

#+:lispworks
(defun quitlisp ()
  (quit))

#+:cmu
(defun quitlisp ()
  (quit))


;;; ------------------- globals for client stuff  --------------------------
(defvar comm_sock nil "Socket used for communication with server")

;;; by default the program runs in client mode, to stop this, pass
;;; either a command line argument, or call the simulation with a
;;; particular function
(defvar clientID  nil "The client ID")

(defvar connection_attempts 50 "Number of attempts to connect to the server before giving up")

(defvar waitforconnection 10 "Waiting before a connection is attempted in sec.")

(defvar receive_attempts 3 "Number of attempts to receive a message")

;;; default for communciation with the server
;;; this will be overwritten by experiment setup file
(defvar servername  "127.0.0.1" "The name of the experiment server, the local host by default")

;;; ONLY CHANGE THIS IN ACCORDANCE WITH SWAGES
(defvar serverport 10010 "The port on the server used for LISP connections by SWAGES")

;;; for non-cluster mode:
;;; used to check whether there is a user on the console
(defvar checkMIGRATION nil "Whether we should perform checks on the host")

(defvar maxtimeconsoleuser 24000 "Max. runtime if use is on console in sec.")

;;; this will save the state of the simulation: saveSTATE * checkINTERVAL = frequency at which simstate is saved
(defvar saveSTATE nil "When to save the simulation state")
(defvar imagename nil "The name of the LISP image if state is saved")

(defvar timercount 0 "number of times the migration check has been performed")

(defvar IDLETIME  30 "idle time of console user before we start a job on his machine")

;;; various bookkeeping variables
(defvar KEEPOUTPUT  nil)
(defvar proxyLOW nil)
(defvar proxyHIGH nil)
(defvar PARALLEL nil)

;;; this will hold the filename of the stats file
(defvar saveSTATSFILE nil)

;;; the file handel for the stats file
(defvar statsout nil)

;;; this will hold the values to be recorded at the beginning and the end
(defvar *beginningrecordings* nil)
(defvar *finalrecordings* nil)

;;; this will hold the seed for this simulation
(defvar ranseed nil)

;;; simulation parameters
(defvar sim_terminate 0)   ;;; for now this is only number, could be a procedure

;;; this is for VM reuse
(defvar firstload t)

;;; holds the current simulation cycle -- needs to be connected to ACTR
;;; (defvar current_cycle 0)
;;; USE: (mp-time) instead

;;; message types
(defconstant PREQ 0)
(defconstant SINT 1)
(defconstant SCNT 2)
(defconstant SPAR 3)
(defconstant CPAR 4)
(defconstant DONE 5)
(defconstant SSAV 6)
(defconstant CCYC 7)
(defconstant PCYC 8)
(defconstant PSAV 9)
(defconstant SPLT 10)
(defconstant ALLD 11)
(defconstant UCID 12)

;;; acknowledgements
(defconstant OK 1)
(defconstant NOTOK 2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; the next two functions need to be provided by the user in init files...
;;; the model-run function, needs to be overwritten with code during simulation setup
(defun run-simulation (params)
  (print "These are the parameters passed to 'run-simulation': ")
  (print params)
)

;;; the model-reset function, needs to be overwritten with code during simulation setup
(defun reset-simulation ()
  (print "Reset-simulation")
)

;;; sends a message to the server
(defun send_message (senderID mtype data)
  (if (uni-stream-closed comm_sock)
      nil
    (progn
      (uni-send-string comm_sock (write-to-string (list senderID mtype data)))
      (let ((message (read comm_sock)))
	(cond ((not message)
	       (close comm_sock)
	       nil)
	      ((eq message OK)
	       t)
	      (t nil))))))

;;; receives a message and returns it, returns false if there is an unrecoverable problem
(defun receive_message ()
 ;;; wait for input or return if the device is closed
 (let ((message (read comm_sock)))
   (cond ((not message)
	  (close comm_sock)
	  nil)
	 (t ;;;(uni-send-string comm_sock OK)
            (sendone OK comm_sock)
	    message))))

;;; waits for a message of a particular kind, if a message of another kind is received instead
;;; it writes a packet with the specific packet request
(defun wait_for_message (typeofmessage)
  ;;; wait for input or return if the device is closed
  (let ((message 
	 (do ((m (receive_message)))
	     ((and (not (null m)) (eq (cadr m) typeofmessage)) m)
	   (sendone NOTOK comm_sock))))
    ;;;(uni-send-string comm_sock OK)
    message))

;;; this will try to send a message and if it does not succeed, it
;;; will reopen a new socket uses the globals: comm_sock, servername,
;;; and serverport
(defun keep_sending_message (mID mtype mdata) 
  (dotimes (n connection_attempts nil)
    (when (send_message mID mtype mdata) 
      (return t))
    	;;; close socket and reestablish connection to server and send
    	;;; ID, so the server
    (close comm_sock)
    (setq comm_sock (uni-make-socket servername serverport))
    (sleep (* 100 waitforconnection))))

;;; this function will perform the necessary setup, including
;;; setting globals, the setting up variable recording, etc. and 
;;; running the simulation at the end...
;;; HIGHLY INCOMPLETE...
(defun parseparameters (params)
  (block parse
    (unless (null params)
      (let* ((p (car params))
	     (key (car p))
	     (val (cadr p)))     
	(cond ((equal key 'initfile)
	       (load val))
	      ;;; this will load the initfile only the first time
	      ((equal key 'initfileonce) 
	       (if firstload
		   (load val)))
	      ((equal key 'compilehere)
	       (eval val))
	      ((equal key 'statsfile)
	       (setf saveSTATSFILE val))	      
	      ((equal key 'ranseed)
	       (setf ranseed val)) ;;; store the seed, will be seeded before the model starts
	      ((equal key 'quitif)
               ;;; for now assume its always the cycle number...	     
               ;;;	     (if (numberp key)
	       (setf sim_terminate val))
	      ;;; set global variable
              ((equal key 'setglobal)
	       (eval `(setf ,val ,(eval (caddr p)))))
	      ;;; set global act variable
              ((equal key 'setglobalact)
	       (eval `(sgp ,val ,(eval (caddr p)))))
	      ;;; TODO: implement saving state... 
              ((equal key 'savestate)
	       (setf saveSTATE val)
	       (setf imagename (caddr p)))
	      ;;; for recording variables... only hook in once 
	      ((equal key 'record-as)
	       (if firstload
	           ;;;  get the car which has the time...
		   (let* ((vars (cdr p))
			  (which (cadr vars))
			  (whenwhat (car (cddr vars)))
			  (final (cadr (cddr vars)))
			  (fargs (cddr (cddr vars))) ;;; potentially args to a function, nil otherwise
                          ;;; first check the different final types...
			  (expr (handler-case
				    (cond ((functionp final) ;;; this does not work right yet...
					   (lambda () (apply final fargs)))
					  ((or (symbolp final) (listp final))
					   (lambda () (eval final)))
					  (t (lambda () "ERROR: unknown expression type for recording.")))
				  (undefined-symbol (v) (print v))
				  (undefined-function (v) (print v)))))
                     ;;; now parse the four types
                     ;;; (record-as <name> in <function-name> {variable|expression|function args})
                     ;;; (record-as <name> at {start|end|<cycle>} {variable|expression|function args})
                     ;;; (record-as <name> every <interval> {variable|expression|function args})
		     (cond ((equal which 'in)
                            ;;; get the function, add the record statement at the end, and 
			    (let ((oldfunc (symbol-function whenwhat)))
                              ;;; set the old function symbol to the new wrapper
			      (setf (symbol-function whenwhat) 
                                #'(lambda (&rest args) (apply oldfunc args)
                                                       ;;; this prints the variable name, the time slot, and the value to the statsfile
                                                       ;;; TODO: PUT THIS INTO A HASHTABLE AND PRINT AT END...
					  (format statsout "~A ~A ~A~%" val (mp-time) (funcall expr))))))
                           ;;; get the "at" parameters
			   ((equal which 'at)
			    (cond ((equal whenwhat 'start)
				   (setf *beginningrecordings* (cons (cons val expr) *beginningrecordings*)))
				  ((equal whenwhat 'end)
				   (setf *finalrecordings* (cons (cons val expr) *finalrecordings*)))
				  ((numberp whenwhat)
				   "TODO: deal with in-between recording") ;;; this needs to be scheduled through ACT-R...
				  ((t (print "Problem with 'record' value...")))))
                           ;;; get the "every" parameters
			   ((equal which 'every)
			    "TODO: deal with cyclic recording")	;;; this needs to be scheduled through ACT-R
			   (t (print "Unknown recording time/place"))))))	      
              ;;;           
	      (t (print "Unknown key...")
		 (print key)
		 (return-from parse))))
      (parseparameters (cdr params)))))


;;; this function is the main entry point for the client
;;; it gets all the simulation parameters from the host
(defun runclient (params)
  ;;; make yourself independent of the calling shell
  ;;; the father returns immediately, only the child continues
  ;;; do we need to do this???
  ;;; if sys_fork(true) then 
  ;;;	return;	
  ;;;  endif;
  ;;; if verbose then npr('runclient executing') endif;
  
  ;;; get server, port, clientID
  (setq servername (car params))
  (setq serverport (cadr params))

  ;;; create the socket
  (setq comm_sock (uni-make-socket servername serverport))

  ;;; loop for VM reuse, get the clientID from the inital parameters
  (do ((clientID (caddr params)))
      ;;; call the respective exit function if we have no clientID
      ((not (stringp clientID)) (quitlisp))

    ;;; reset the global recording lists
    (setf *beginningrecordings* nil)
    (setf *finalrecordings* nil)

    ;;; request the parameters and parse them
    (do ((simparammessage nil))
        ;;; evaluate the first part and parse the simulation parameters
	((not (null simparammessage))
          ;;; and then parse the parameters
	 (parseparameters (car (caddr simparammessage))))
      ;;; request parameters for client "clientID"
      (keep_sending_message clientID PREQ nil)  
      (if verbose (print "Sent PREQ"))
      (setq simparammessage (wait_for_message SPAR))
      (if verbose (print "Got SPAR"))
      (force-output *standard-output*)

    (if verbose (print ""))
    (print (symbol-function 'run-simulation))

    
    ;;; set first load to false in case we're reusing the
    (setq firstload nil)
    
    ;;; open the stats file, create if it does not exist yet
    (setq statsout (open saveSTATSFILE :direction :output :if-exists :overwrite :if-does-not-exist :create))
    
    ;;; here the model must be already loaded, so seed the random number generator
    (eval (list 'sgp ':seed (list ranseed 0)))
    
    (when *beginningrecordings*
      (mapcar #'(lambda (___x) (format statsout "~A ~A ~A~%" (car ___x) (mp-time) (funcall (cdr ___x)))) *beginningrecordings*))
    
    ;;; run simulation on the simparam entry in the message
    (if verbose (print "Simulation started"))
    (print (symbol-function 'run-simulation))
    (force-output *standard-output*)
    (run-simulation sim_terminate)
    (if verbose (print "Simulation finished"))
    
    ;;; record the final values
    (when *finalrecordings*
      (mapcar #'(lambda (___x) (format statsout "~A ~A ~A~%" (car ___x) (mp-time) (funcall (cdr ___x)))) *finalrecordings*))
    (close statsout)

    ;;; tell the server that the client has finished, include the final cycle number
    (setq statsout (open saveSTATSFILE :direction :input))
    (keep_sending_message clientID DONE (list (mp-time) (file-length statsout)))
    (close statsout)
    
    ;;; wait for another clientID if reuseVM or quit
    (setq clientID (caddr (wait_for_message UCID)))
    ;;; if we got a new ID, the VM will be re-used, so reset the simulation
    (if (stringp clientID) 
	;;; reset the simulation
	(reset-simulation)))
)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                              comlink/CLList.java                                                                                 0000664 0000764 0000764 00000001023 10621412774 015007  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 *
 * SWAGES 1.1
 *
 * (c) by Matthias Scheutz
 *
 * Common Lisp list representation
 *
 * Last modified: 05-12-07
 *
 ********************************************************************/

package comlink;

// convenience class for CL lists
import java.util.ArrayList;
import java.io.Serializable;

public class CLList<E> extends ArrayList<E> implements Serializable {
    public CLList(int l) {
	super(l);
    }
    public CLList() {
        super();
    }
}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             comlink/CLSymbol.java                                                                               0000664 0000764 0000764 00000000654 10621413146 015344  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Common Lisp symbol representation
 * 
 * Last modified: 05-12-07
 * 
 ********************************************************************/

package comlink;

import java.io.Serializable;

public class CLSymbol extends Word implements Serializable {
    public CLSymbol(String s) {
	super(s);
    }
}
                                                                                    comlink/CLSyntaxError.java                                                                          0000664 0000764 0000764 00000000576 10544550010 016376  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Common Lisp syntax error
 * 
 * Last modified: 12-28-06
 * 
 ********************************************************************/

package comlink;

public class CLSyntaxError extends SyntaxError {
    public CLSyntaxError(String s) {
	super(s);
    }
}
                                                                                                                                  comlink/ComLink.java                                                                                0000664 0000764 0000764 00000141724 10635535513 015230  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 *
 * SWAGES 1.1
 *
 * (c) by Matthias Scheutz <mscheutz@nd.edu>
 *
 * Utilities to interact with other language environments over sockets
 * (including Pop11 and Common Lisp)
 *
 * Last modified: 06-18-07
 *
 *********************************************************************/

package comlink;

import java.util.*;
import java.io.*;
import java.net.*;
import java.lang.reflect.*;
import java.math.*;

// provides serialization for different languages and socket communication
public class ComLink {
    // set to true to print debug messages
    private static final boolean debug = false;
    private static final boolean strict = true;

    // this will hold the deserializer method for class types so they have to be looked up only once
    private static final Hashtable deserializers = new Hashtable();

    // support for different languages 
    // NOTE: these need to start from 0 as they are used for indices in a mapping from clients to languages
    public static final String[] supportedlanguages = new String[]{"JAVA","pop11","Common Lisp","R"};
    public static final int RAW = -1;   // take it as it comes... do not try to deserialize    
    public static final int JAVA = 0;   // not fully implemented yet
    public static final int POP11 = 1;
    public static final int CL = 2;
    public static final int R = 3;      // not fully implemented yet
    
    // message acknowledgements
    public static final int OK = 1;
    public static final int NOTOK = -1;

    /* socket communication in CLISP:
       (setq s (uni-make-socket "127.0.0.1" 10000))
       (uni-send-string s (write-to-string '(1 2 3))
    */

    @SuppressWarnings("unchecked")
    public static ArrayList cons(Object o,ArrayList v) {
        v.add(0,o);
        return v;
    }

    // parses an expression in a file for a given language
    public static Object parseExpression(File f,int language) throws IOException, SyntaxError {
	char[] buffer = new char[(int)f.length()];
	FileReader fr = new FileReader(f);

    // Fill buffer with entire file contents - RM
    int count = fr.read(buffer);
    int index = count;
    while( index < buffer.length ) {
        count = fr.read( buffer, index, buffer.length - index );
        index += count;
    }

	fr.close();
	return parseExpression(new String(buffer),language);
    }

    // call the appropriate parsing function
    public static Object parseExpression(String s,int language) throws SyntaxError {
	switch(language) {
	case RAW:
        case JAVA:
	    return s;
	case POP11:
	    return parseExpressionPop11(s);
	case CL:
	    return parseExpressionCL(s);
	case R:
	    return parseExpressionR(s);
	default:
	    if (strict) throw new SyntaxError("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    return null;
	}
    }
    
    // parse pop11 expressions
    @SuppressWarnings("unchecked")
    public static Object parseExpressionPop11(String s) throws Pop11SyntaxError {
	ArrayList ret = null;
	Stack stk = new Stack();
	boolean parsingstring = false;

	// get the list structure out, if there is any
	StringTokenizer st = new StringTokenizer(s,"{}[]'\"",true);
	while (st.hasMoreTokens()) {
	    String token = st.nextToken();
	    //System.out.println("Token is: " + token);
            if (token.equals("[")) {
		if (parsingstring) {
		    if (strict) throw new Pop11SyntaxError("Unexpected [ in string.");
		    System.err.println("Problem parsing POP11 expression: " + s);
		    return null;
		}
		// start of a new list, so push the current ArrayList if not null
		if (ret != null)
		    stk.push(ret);
		ret = new Pop11List();
		//System.out.println("new vec");
	    }
            else if (token.equals("{")) {
		if (parsingstring) {
		    if (strict) throw new Pop11SyntaxError("Unexpected { in string.");
		    System.err.println("Problem parsing POP11 expression: " + s);
		    return null;
		}
		// start of a new ArrayList, so push the current ArrayList if not null
		if (ret != null)
		    stk.push(ret);
		ret = new ArrayList();
		//System.out.println("new vec");
	    }
	    else if (token.equals("]")) {
		// end of a list, so wrap up the ArrayList, place it in the one on the stack
		// and restore ret
		if (parsingstring) {
		    if (strict) throw new Pop11SyntaxError("Unexpected ] in string.");
		    System.err.println("Problem parsing POP11 expression: " + s);
		    return null;
		}
		if (!stk.empty()) {
		    ArrayList temp = (ArrayList)stk.pop();		    
		    temp.add(ret);
		    ret = temp;
		}
		else
		    return ret;
	    }
	    else if (token.equals("}")) {
		// end of a ArrayList, so wrap up the ArrayList, place it in the one on the stack
		// and restore ret
		if (parsingstring) {
		    if (strict) throw new Pop11SyntaxError("Unexpected } in string.");
		    System.err.println("Problem parsing POP11 expression: " + s);
		    return null;
		}		
		if (!stk.empty()) {
		    ArrayList temp = (ArrayList)stk.pop();		    
		    temp.add(ret);
		    ret = temp;
		}
		/*	else if (st.hasMoreTokens()) {
		    token = st.nextToken();
		    if (token.equals("\r") || token.equals("\n"))
			return ret;
		    if (strict) throw new Pop11SyntaxError("Unexpected end of expression reading " + token);
		    System.err.println("Problem parsing POP11 expression: " + s);
		    return null;
		}*/
		else
		    return ret;
	    }
	    else if (token.equals("'"))
		parsingstring = !parsingstring;
	    else if (!token.equals("\r") && !token.equals("\n")) {
		// it is a string without lists, so parse it into parts
		String[] result = (parsingstring ? new String[]{token} : token.split("\\s"));
		
		if (result.length > 1 && ret == null) {
		    if (strict) throw new Pop11SyntaxError("Pop11: multiple expressions without a list.");
		    System.err.println("Problem parsing POP11 expression: " + s);
		    return null;
		}		
		for (int x=0; x<result.length; x++) {

		    Object value = null;
		    try {
			// check if it is an integer
			value = Integer.valueOf(result[x]);
		    } catch (NumberFormatException e1) {
			try {
			    // or a BigDecimal
			    value = new BigDecimal(result[x]);
			} catch (NumberFormatException e2) {
			    // must be a either a string or a pop11 word
			    if (parsingstring)
				value = result[x];
			    else if (result[x].equals("true"))
				value = new Boolean(true);
			    else if (result[x].equals("false"))
				value = new Boolean(false);
			    else
				value = new Pop11Word(result[x]);
			}
		    }    
		    /*
		    if (result.length == 1 && stk.empty()) {
                        System.out.println("*******************");
			return value;
                    }
		    else
                     */ 
                        
                    if (ret != null)
			ret.add(value);
		    else {
			if (strict) throw new Pop11SyntaxError(s);		    
			System.err.println("Problem parsing POP11 expression: " + value);
			return null;
		    }
		}
	    }
	}	
	return ret;
    }

    
    // R deserialization
    // TODO: need to implement it...
    // For now we simply use the LISP tokenizer for the message structure as we the rclient
    // produceds a LISP list expression
    public static Object parseExpressionR(String s) throws RSyntaxError {
	// get the list structure out, if there is any
	// StringTokenizer st = new StringTokenizer(s,"()\'\"`,;#\n\t\r",true);
	// return s; // parseRExpression(st,false);
	try {
	    return parseExpressionCL(s);
	} catch (CLSyntaxError e) {
	    throw new RSyntaxError(e.toString());
	}
    }

    // helper function for parsing Rexpressions
    //@SuppressWarnings("unchecked")
    //private static Object parseRExpression(StringTokenizer st,boolean allowcommas) throws RSyntaxError {
    // SEE CODE BELOW FOR CLISP...
    
    
    // Common Lips deserialization
    // TODO: need to handle strings correctly
    //
    public static Object parseExpressionCL(String s) throws CLSyntaxError {
	// get the list structure out, if there is any
	StringTokenizer st = new StringTokenizer(s,"()\'\"`,;#\n\t\r",true);
	return parseCLExpression(st,false);
    }

    // helper function for parsing LISP expressions
    @SuppressWarnings("unchecked")
    private static Object parseCLExpression(StringTokenizer st,boolean allowcommas) throws CLSyntaxError {
	ArrayList ret = null;
	Stack stk = new Stack();
	boolean parsingstring = false;
	boolean incomment = false;
	String currentstring = "";

	while (st.hasMoreTokens()) {
	    String token = st.nextToken();
	    if (debug) System.out.println("Token is: " + token);
	    // check if we are in a comment and just skip tokens until we hit newline or EOF
            if (incomment) {
		if (debug) System.out.println("In comment, skipping " + token);
		if (token.equals("\n")) {
		if (debug) System.out.println("End comment");
		    incomment = false;
		}
		// otherwise just skip the token for now, should record the comment though...
	    }
	    else if (parsingstring) {
		if (debug) System.out.println("In string");
		if (token.equals("\"")) {
		    if (debug) System.out.println("End string, string is: " + currentstring);
		    parsingstring = false;
		    if (ret == null)
			return currentstring;
		    else 
			ret.add(currentstring);
			currentstring="";
		}
		else {
		    if (debug) System.out.println("Adding to string: " + token);
		    // add to string
		    currentstring = currentstring + token;
		}
	    }
	    else if (token.equals("\n") || token.equals("\t") || token.equals("\r")) {
		// whitespace, skip it
	    }
	    // start reading comment
            else if (token.equals(";")) {
		if (debug) System.out.println("Starting comment");
		incomment = true;
	    }
            else if (token.equals(",")) {
		if (debug) System.out.println("Found comma ");
		// check if commas are allowed
		if (allowcommas)
		    ret.add(new CLSymbol(token));
		else {
		    if (strict) throw new CLSyntaxError(token);		    
		    System.err.println("Problem parsing LISP expression: " + token);
		    return null;
		}
	    }
            else if (token.equals("#")) {
                // TODO: need to handle this for function symbols, i.e., #'...
		System.out.println("WARNING: # not implemented yet!");
	    }
            else if (token.equals("`")) {
		if (debug) System.out.println("Found backquote");
		System.out.println("WARNING: ` not fully implemented yet");
		// start of a new ArrayList, so push the current ArrayList if not null
		if (ret != null)
		    stk.push(ret);
		ret = new Pop11List();
		// add the special form "quote" as the first element, 
		// the next element needs to be an expression...
		CLSymbol cmd = new CLSymbol("quote");
		ret.add(cmd);
		ret.add(parseCLExpression(st,true));
		// mark it as backquoted list...
		cmd.backquote = true;
		//System.out.println("new vec");
		if (!stk.empty()) {
		    ArrayList temp = (ArrayList)stk.pop();		    
		    temp.add(ret);
		    ret = temp;
		}
		else
		    return ret;
	    }
            else if (token.equals("(")) {
		if (debug) System.out.println("New list");
		// start of a new list, so push the current ArrayList if not null
		if (ret != null)
		    stk.push(ret);
		ret = new Pop11List();
		//System.out.println("new vec");
	    }
            else if (token.equals("\'")) {
		if (debug) System.out.println("New quote");
		if (ret != null)
		    stk.push(ret);
		ret = new Pop11List();
		// add the special form "quote" as the first element, 
		// then the next element needs to be an expression...
		CLSymbol cmd = new CLSymbol("quote");
		ret.add(cmd);
		ret.add(parseCLExpression(st,allowcommas));
		if (!stk.empty()) {
		    ArrayList temp = (ArrayList)stk.pop();		    
		    temp.add(ret);
		    ret = temp;
		}
		else
		    return ret;
		//System.out.println("new vec");
	    }
	    else if (token.equals(")")) {
		if (debug) System.out.println("End list");
		// end of a list, so wrap up the ArrayList, place it in the one on the stack
		// and restore ret
		if (!stk.empty()) {
		    ArrayList temp = (ArrayList)stk.pop();		    
		    temp.add(ret);
		    ret = temp;
		}
		else
		    return ret;
	    }
	    else if (token.equals("\"")) {
		if (debug) System.out.println("Starting string");	    
		parsingstring = true;
		// must be a string 
	    }
	    else  {
		if (debug) System.out.println("Other tokens...");	    
		// it is a string without lists, so parse it into parts
		// split on whitespace
		String[] result = token.split("\\s");

		if (debug) System.out.println("NUMBER OF SPLIT TOKENS: " + result.length);
		
		if (result.length > 1 && ret == null) {
		    if (strict) throw new CLSyntaxError("LISP: Multiple expressions without a list.");
		    System.err.println("Problem parsing LISP expression: " + token);
		    return null;
		}		
		for (int x=0; x<result.length; x++) {
		    if (result[x].trim().equals(""))
			continue;
		    Object value = null;
		    try {
			// check if it is an integer
			value = Integer.valueOf(result[x]);
		    } catch (NumberFormatException e1) {
			try {
			    // or a BigDecimal
			    value = new BigDecimal(result[x]);
			} catch (NumberFormatException e2) {
			    // must be a either a string or a pop11 word
			    if (parsingstring)
				value = result[x];
			    else if (result[x].equals("t") || result[x].equals("T"))
				value = new Boolean(true);
			    else if (result[x].equals("nil") || result[x].equals("NIL"))
				value = new Boolean(false);
			    else
				value = new CLSymbol(result[x]);
			}
		    }    
		    /*		    
		    if (result.length == 1 && stk.empty()) {
			System.out.println("Returning token " + value);
			return value;
		    }
		    else 
		    */
		    if (ret != null) {
			if (debug) System.out.println("Adding " + value);	    
			ret.add(value);
		    }
		    else {
			return value;
			/*			
			{
			if (strict) throw new Pop11SyntaxError(token);		    
			System.err.println("Problem parsing LISP expression: " + value);
			return null;
			*/
		    }
		}
	    }
	}	
	return ret;
    }    

    // general entry
    public static void produceList(File f,Object o,int language) throws IOException, SyntaxError {	
	FileWriter fr = new FileWriter(f);
	fr.write(produceList(o,language));
	fr.close();
    }
    
    
    // call the appropriate production function
    public static String produceList(Object o,int language) throws SyntaxError {
	switch(language) {
	case JAVA:
        case RAW:
	    return o.toString();
	case POP11:
	    return produceListPop11(o);
	case CL:
	    return produceListCL(o);
        case R:
	    return produceListR(o);
	default:
	    if (strict) throw new SyntaxError("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    return null;
	}
    }
    
    // pop11 list production
    @SuppressWarnings("unchecked")
    public static String produceListPop11(Object o) {
	StringBuffer s = new StringBuffer(1024);
	Stack stk = new Stack();
	boolean lastwasitem = false;
	int indent = 0;
	boolean firstopen = true;
	boolean lastwasclosed = false;
	
	// put the object on the stack
	stk.push(o);
	while (!stk.empty()) {
	    o = stk.pop();
	    if (o instanceof ArrayList) {
		ArrayList v = (ArrayList)o;
		// put the closing bracket on the stack as a delimiter
		stk.push(new Character(']'));
		// put all elements on the stack in reversed order
		for(int i = v.size()-1; i>=0; i--)		    
		    stk.push(v.get(i));
		// write the open list bracket
		if (!firstopen && !lastwasclosed)
		    s.append('\n');
		for (int k=0; k<indent; k++)
		    s.append(' ');
		s.append('[');
		indent++;
		lastwasitem = false;
		lastwasclosed = false;
		firstopen = false;
	    }
	    else if (o instanceof Character) {
		if (((Character)o).charValue() == ']') {
		    indent--;
		    if (lastwasclosed) {
			for (int k=0; k<indent; k++)
			    s.append(' ');
		    }
		    s.append(o);
		    s.append('\n');
		    lastwasclosed = true;		
		    lastwasitem = false;
		}
		else {
		    if (lastwasitem)
			s.append(' ');
		    s.append(o);
		    lastwasitem = true;
		    lastwasclosed = false;					
		}
	    }
	    else {
		if (lastwasitem)
		    s.append(' ');
		if (o instanceof Word)
		    s.append(((Word)o).word);
		else if (o instanceof String)
		    s.append("'" + o + "'");		
		else
		    // must have been a number, just append it
		    s.append(o);
		lastwasitem = true;
		lastwasclosed = false;		
	    }
	}
	return s.toString();
    }

    
    // R list production
    // TODO: finish....
    // for now we produce simple R list expressions that can be parsed by R
    @SuppressWarnings("unchecked")
    public static String produceListR(Object o) throws RSyntaxError {
	StringBuffer s = new StringBuffer(1024);
	Stack stk = new Stack();
	boolean lastwasitem = false;
	int indent = 0;
	boolean firstopen = true;
	boolean lastwasclosed = false;

	// put the object on the stack
	stk.push(o);
	while (!stk.empty()) {
	    o = stk.pop();
	    if (o instanceof ArrayList) {
		ArrayList v = (ArrayList)o;
		// check if it is a quote or backquote structure
		if (v.size() > 0) {
		    Object fo = v.get(0);
		    if ((fo instanceof Word) &&(((Word)fo).word).equals("quote")) {
                        if (((CLSymbol)fo).backquote) {
                            s.append(" `");
                        }
                        else {
                            s.append(" \'");
                        }
                        if (v.size()>2) {
                            if (strict) throw new RSyntaxError("Illegal quote construct: " + v);
                            System.err.print("Illegal quote construct: " + v);
                            return null;
                        }
                        stk.push(v.get(1));
                        lastwasitem = false;
                        firstopen = true;                        
		    }
		    else {
			stk.push(new Character(')'));
			// put all elements on the stack in reversed order
			for(int i = v.size()-1; i>=0; i--) {
			    stk.push(v.get(i));
			    if (i>0)
				stk.push(new Character(','));
			}
			// write the open list bracket
			//if (!firstopen && !lastwasclosed) {
			    //s.append("\n");
			  //  for (int k=0; k<indent; k++)
			//	s.append(' ');
			//}
			s.append("list(");
			//indent++;
			lastwasitem = false;
			firstopen = false;
		    }
		}
		else {
		    s.append("list()");
		    lastwasitem = true;
		    firstopen = false;
		}
		lastwasclosed = false;
	    }
	    else if (o instanceof Character) {
		if (((Character)o).charValue() == ']') {
		    //indent--;
		   // if (lastwasclosed) {
			//for (int k=0; k<indent; k++)
			//    s.append(' ');
		    //}
		    s.append(o);
		    //s.append('\n');
		    lastwasclosed = true;		
		    lastwasitem = false;
		}
		else {
		    if (lastwasitem)
			s.append(' ');
		    s.append(o);
		    lastwasitem = true;
		    lastwasclosed = false;					
		}
	    }
	    else {
		if (lastwasitem)
		    s.append(' ');
		lastwasitem = true;
		lastwasclosed = false;		
		if (o instanceof Word) {
		    if ((((Word)o).word).equals(",")) {
			s.append(',');		
			lastwasitem = false;
		    }
                    else {
                        s.append("quote(" + (((Word)o).word) + ")");
                    }		    
		}
		else if (o instanceof String)
		    s.append("\"" + o + "\"");
                // map "null" onto the empty list
		else if (o == null)
                    s.append("list()");		
                else
		    // must have been a number, just append it
		    s.append(o);
	    }
	}
	return s.toString();
    }



    // CL list production
    //
    @SuppressWarnings("unchecked")
    public static String produceListCL(Object o) throws CLSyntaxError {
	StringBuffer s = new StringBuffer(1024);
	Stack stk = new Stack();
	boolean lastwasitem = false;
	int indent = 0;
	boolean firstopen = true;
	boolean lastwasclosed = false;

	// put the object on the stack
	stk.push(o);
	while (!stk.empty()) {
	    o = stk.pop();
	    if (o instanceof ArrayList) {
		ArrayList v = (ArrayList)o;
		// check if it is a quote or backquote structure
		if (v.size() > 0) {
		    Object fo = v.get(0);
		    if (fo instanceof CLSymbol && (((CLSymbol)fo).word).equals("quote")) {
			if (((CLSymbol)fo).backquote) {
			    s.append(" `");
			}
			else {
			    s.append(" \'");
			}
			if (v.size()>2) {
			    if (strict) throw new CLSyntaxError("Illegal quote construct: " + v);
			    System.err.print("Illegal quote construct: " + v);
			    return null;
			}
			stk.push(v.get(1));
			lastwasitem = false;
			firstopen = true;
		    }
		    else {
			stk.push(new Character(')'));
			// put all elements on the stack in reversed order
			for(int i = v.size()-1; i>=0; i--)		    
			    stk.push(v.get(i));
			// write the open list bracket
			if (!firstopen && !lastwasclosed) {
			    s.append('\n');
			    for (int k=0; k<indent; k++)
				s.append(' ');
			}
			s.append('(');
			indent++;
			lastwasitem = false;
			firstopen = false;
		    }
		}
		else {
		    s.append(" ()");
		    lastwasitem = true;
		    firstopen = false;
		}
		lastwasclosed = false;
	    }
	    else if (o instanceof Character) {
		if (((Character)o).charValue() == ']') {
		    indent--;
		    if (lastwasclosed) {
			for (int k=0; k<indent; k++)
			    s.append(' ');
		    }
		    s.append(o);
		    s.append('\n');
		    lastwasclosed = true;		
		    lastwasitem = false;
		}
		else {
		    if (lastwasitem)
			s.append(' ');
		    s.append(o);
		    lastwasitem = true;
		    lastwasclosed = false;					
		}
	    }
	    else {
		if (lastwasitem)
		    s.append(' ');
		lastwasitem = true;
		lastwasclosed = false;		
		if (o instanceof Word) {
		    if ((((Word)o).word).equals(",")) {
			s.append(',');		
			lastwasitem = false;
		    }
		    else
			s.append(((Word)o).word);
		}
		else if (o instanceof String)
		    s.append("\"" + o + "\"");		
                // map "null" onto the empty list
		else if (o == null)
                    s.append("()");		
		else
		    // must have been a number, just append it
		    s.append(o);
	    }
	}
	return s.toString();
    }
    

    // reads an object from an existing socket and returns the error status at the end
    public static Object read(Socket s, int language) throws IOException {
	BufferedReader in = new BufferedReader(new InputStreamReader(s.getInputStream()));
	return read(in,language);
    }

    public static Object read(BufferedReader in,int language) throws IOException {
        return read(in,language,true);
    }
    
    public static Object read(BufferedReader in,int language, boolean waitforline) throws IOException {
	switch(language) {
	case RAW:
        case JAVA:            
	    //try {
	    return in.readLine();  // TODO: make this ready as many lines a necessary...
	    //} catch(Pop11SyntaxError e) {
	    //throw new IOException(e.toString());
	    // }
	case POP11:
	    return datafread(in);
	case CL:
	    try {
                if (!waitforline) {
                    try {
                        while(!in.ready())
                            Thread.sleep(100);
                    } catch (InterruptedException ie) {}
                    Integer i = new Integer(in.read());
                    //System.err.println("------> " + i);  
                    return i;
                }
                else {
                    String line = null;
                    try {
                        while ((line = in.readLine()) == null) {
                            Thread.sleep(100);
                        }
                        // now read as many lines as there are waiting...
                        while (in.ready())
                            line += "\n" + in.readLine();                        
                    } catch(InterruptedException e) {}
                    //System.err.println("======> " + parseExpressionCL(line));
                    return parseExpressionCL(line); 
                }
	    } catch(CLSyntaxError e) {
		throw new IOException(e.toString());
	    }
	case R:
	    try {
		//	    String s;
		//char c;
		//while ((c = in.read()) != -1)
		String line = null;
		try {
                    while ((line = in.readLine()) == null) {
                        System.out.println("TRYING TO READ IT...");
                        Thread.sleep(100);
                    }
                    // now read as many lines as there are waiting...
                    while (in.ready())
                        line += "\n" + in.readLine();     
                } catch(InterruptedException e) {}
		return parseExpressionR(line);
	    } catch(RSyntaxError e) {
		throw new IOException(e.toString());
	    }
            
	default:
	    if (strict) throw new IOException("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    return null;
	}
    }

    // writes an object into an existing socket and returns the error status at the end
    public static Object read(File f,int language) throws IOException {
	switch(language) {
        case RAW:
            try {
		return parseExpression(f,RAW);
	    } catch(SyntaxError e) {
		throw new IOException(e.toString());
	    }
	case JAVA:        
	    try {
		return parseExpression(f,JAVA);
	    } catch(SyntaxError e) {
		throw new IOException(e.toString());
	    }
	case POP11:
	    FileReader in = new FileReader(f);
	    return datafread(in);
	case CL:
	    try {
		return parseExpression(f,CL);
	    } catch(SyntaxError e) {
		throw new IOException(e.toString());
	    }
	case R:
	    try {
		return parseExpression(f,R);
	    } catch(SyntaxError e) {
		throw new IOException(e.toString());
	    }
	default:
	    if (strict) throw new IOException("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    return null;
	}
    }

    // writes an object into a string and returns
    public static Object read(String str,int language) throws IOException, SyntaxError {
	switch(language) {
        case RAW:                
	case JAVA:
	    //try {
	    return str;
	    //} catch(Pop11SyntaxError e) {
	    //throw new IOException(e.toString());
	    //}
	case POP11:
	    StringReader sr = new StringReader(str);
	    return datafread(sr);
	case CL:
            return parseExpression(str,CL);
	case R:
            return parseExpression(str,R);
	default:
	    if (strict) throw new IOException("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    return null;
	}
    }
        
    // the actual pop11 read function
    @SuppressWarnings("unchecked")
    static private Object datafread(Reader r) throws IOException {       	
	final StreamTokenizer s = new StreamTokenizer(r);

	class fread {

	    Object datafreadhelper() throws IOException {	
		if (s.nextToken() == s.TT_WORD) 
		    if (s.sval.equals("zl")) {
			s.nextToken();
			int l = (int)s.nval;
			Pop11List v = new Pop11List(l);
			for(int i=0;i<l;i++) {
			    v.add(datafreadhelper());
			}	
			return v;
		    }
		/* NO IMPLEMENTED
		   elseif x == "zp" then
		   conspair(datafread(),datafread()) -> x;
		*/
		    else if (s.sval.equals("zs")) {
			s.nextToken();
			int l = (int)s.nval;
			byte[] stringbytes = new byte[l];
			for(int i=0;i<l;i++) {
			    s.nextToken();
			    stringbytes[i] = (byte)s.nval;
			}
			return new String(stringbytes);
		    }
		    else if (s.sval.equals("zv")) {
			s.nextToken();
			int l = (int)s.nval;
			ArrayList v = new ArrayList(l);
			for(int i=0;i<l;i++) {
			    v.add(datafreadhelper());
			}
			return v;
		    }
		/* NOT IMPLEMENTED
		   else if x == "za" then
		   newarray(datafread()) -> x;
		   datalength(arrayArrayList(x)) -> t;
		   for n from 1 to t do
		   datafread() -> fast_subscrv(n,arrayArrayList(x));
		   endfor;
		   elseif x == "zr" then
		   consref(datafread()) -> x;
		*/
		    else if (s.sval.equals("zb")) {
			s.nextToken();
			return new Boolean(s.sval.equals("true") ? true : false);
		    }
		    else if (s.sval.equals("zw")) {
			s.nextToken();
			int l = (int)s.nval;
			byte[] wordbytes = new byte[l];
			for(int i=0;i<l;i++) {
			    s.nextToken();
			    wordbytes[i] = (byte)s.nval;
			}
			return new Pop11Word(new String(wordbytes));
		    }
		    // MS: new, deserialize class
		    else if (s.sval.equals("zc")) {
			// TODO: if a compiler is available and the class does not exist, then produce it on the fly...
			// get the class name, language is the next token			s.nextToken();
			s.nextToken();
			String key = s.sval;
			boolean trydirect = false;
			Object o = null;
			Class co = null;
			// first get the class denoted by the key
			try {
			    co = Class.forName(key);		
			    // create a new instance of the class...
			    o = co.newInstance();	
			    // } catch (SecurityException e1) {
			    // if (debug) System.out.println("SECURITY");
			} catch (ClassNotFoundException e6) {
			    System.err.println("Class definition not found for pop11 key: " + key);
			    return null;
			} catch (IllegalAccessException e3) {
			    System.err.println("ILLEGAL ACCESS will instantiation class " + key);
			    return null;
			} catch (InstantiationException e7) {
			    System.err.println("Class " + key + " cannot be instantiated");
			    return null;
			}
			// first check if there is a specific serialization method for this class
			try {
			    Method meth = null;
			    Object[] newargs = null;
			    ArrayList al;
			    int numargs = 0;
			    // check the stored ones
			    if ((al = (ArrayList)deserializers.get(key)) == null) {
				// did not find it, so look it up
				// get all methods and then find the one called "fromPop11"
				// NOTE: THIS WILL NOT WORK IF THERE ARE MULTIPLE SUCH METHODS...
				Method[] meths = co.getDeclaredMethods();
				for(int i = 0; i< meths.length; i++) {
				    meth = meths[i];
				    // check if it is the "fromPop11" method
				    if (meth.getName().equals("fromPop11"))
					break;
				    meth = null;
				}
				if (meth == null) {
				    if (debug) System.err.println("Class " + key + " does not have a 'fromPop11' method!");
				    trydirect = true;
				} 
				else {
				    // create a non-synchronized list
				    al = new ArrayList(2);
				    al.add(meth);
				    newargs = new Object[meth.getParameterTypes().length];
				    al.add(newargs);
				    // store the method plus the argument number in the Hashtable under the class key
				    deserializers.put(key,al);
				}
			    }
			    // otherwise we already have them in the Hashtable, so get them
			    else {
				meth = (Method)al.get(0);
				newargs = (Object[])al.get(1);
			    }
			    // check if we have to try it the direct way
			    if (!trydirect) {
				// TODO: we could check that the types are OK too
				for(int i=0; i<newargs.length; i++) {
				    newargs[i] = datafreadhelper();
				}
				// now invoke the deserializer on the arguments
				meth.invoke(o,newargs);
				return o;
			    }
			} catch (SecurityException e1) {
			    if (debug) System.err.println("Access to pop11 field serializer denied in class " + key);
			} catch (IllegalAccessException e2) {
			    if (debug) System.err.println("Access to pop11 field serializer denied in class " + key);
			} catch (InvocationTargetException e3) {
			    if (debug) System.err.println("Cannot invoke field serializer defined in class " + key);
			}
			// if we get here then errors occured above (e.g., we don't have the deserializer), so try it directly
			try {
			    // now get the fields
			    Field[] fs = co.getDeclaredFields();
			    // read in the fields one by one--THIS will cause an exception if not all fields are Public!
			    for(int f=0;f<fs.length;f++)
				// got the fields, so put them on the stack, one by one
				// set the value of the field in the object to the serialized value
				fs[f].set(o,datafreadhelper());
			} catch (SecurityException e1) {
			    if (debug) System.out.println("SECURITY");
			} catch (IllegalAccessException e2) {
			    if (debug) System.out.println("ILLEGAL ACCESS");
			} catch (IllegalArgumentException e3) {
			    if (debug) System.out.println("ILLEGAL ARGUMENT");
			} catch (NullPointerException e4) {
			    if (debug) System.out.println("NULL POINTER");
			} catch (ExceptionInInitializerError e5) {
			    if (debug) System.out.println("INITIALIZER");
			}
			return o;				
		    }
		/* NOT IMPLEMENTED
		   elseif x == "zu" then
		   ;;; get ArrayListclass - Aled, June 1st, 1987
		   datafread() -> t;
		   key_of_dataword(t) -> key;
		   unless key then
		   mishap('Unknown dataword encountered in datafile\n' >< ';;;          (ArrayListclass declaration not loaded?)', [^t]);
		   endunless;
		   repeat (datafread() ->> t) times datafread() endrepeat;
		   apply(t, class_cons(key)) -> x
		*/
		    else if (s.sval.equals("zh")) {
			Hashtable h = new Hashtable();
			ArrayList v = (ArrayList)datafreadhelper();
			for(int i=0;i<v.size();i++) {
			    ArrayList pair = (ArrayList)v.get(i);
			    h.put(pair.get(0),pair.get(1));
			}
			// ignore the size, the default index, and the storage property
			s.nextToken();
			s.nextToken();
			s.nextToken();
			return h;
		    }
		    // don't the key, error
		    else return null;
		else {
		    int d = (int)s.nval;
		    if ((double)d == s.nval)
			return new Integer((int)s.nval);
		    else
			return new BigDecimal(s.nval);
		}
		/* NO IMPLEMENTED
		   elseif x == "zC" then
		   rditem() -> t;
		   partapply(valof(t),datafread()) -> x;
		   elseif x == "zP" then
		   valof(rditem()) -> x;
		*/
		// should never get here...
	    }
	}
	return new fread().datafreadhelper();
    }
    
    
    // writes an object into an existing socket and returns the error status at the end
    public static void write(Socket s,Object o,int language) throws IOException {
	PrintWriter out = new PrintWriter(s.getOutputStream(),false);
        write(out,o,language);
    }


    // writes an object into an existing socket and returns the error status at the end
    public static void write(PrintWriter out,Object o,int language) throws IOException {        
	switch(language) {
        case RAW:
            out.write(o.toString());
            break;
        case JAVA:
	    try{
		out.write(produceList(o,0));
	    } catch(SyntaxError e) {
		throw new IOException(e.toString());
	    }
	    break;
	case POP11:
	    datafwrite(out,o);
	    break;
	case CL:
	    try {                
		out.write(produceListCL(o));
                //System.err.println("~~~~~~> " + o);  
	    } catch(CLSyntaxError e) {
		throw new IOException(e.toString());
	    }
	    break;
	case R:
	    try {
                //System.out.println(produceListR(o));
		out.write(produceListR(o));                
	    } catch(RSyntaxError e) {
		throw new IOException(e.toString());
	    }
	    break;
	default:
	    if (strict) throw new IOException("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    break;
	}
	out.write('\n');
	out.flush();
	if (out.checkError())
	    throw new IOException("Problem with socket in datafwrite");
    }

    // writes an object into a file and returns
    // MS: added newline at the end to make the files identical to pop11
    public static void write(File f,Object o,int language) throws IOException {
	FileWriter fw = new FileWriter(f);
	switch(language) {
	case RAW:
            fw.write(o.toString());
            break;
        case JAVA:
	    try{
		fw.write(produceList(o,0));
	    } catch(SyntaxError e) {
		throw new IOException(e.toString());
	    }
	    break;
	case POP11:
	    datafwrite(fw,o);
	    break;
	case CL:
	    try{
		fw.write(produceListCL(o));
	    } catch(CLSyntaxError e) {
		throw new IOException(e.toString());
	    }
	    break;
	case R:
	    try{
		fw.write(produceListR(o));
	    } catch(RSyntaxError e) {
		throw new IOException(e.toString());
	    }
	    break;	default:
	    if (strict) throw new IOException("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    break;
	}
	fw.flush();
	fw.close();
    }

    // writes an object into a string and returns
    public static String write(Object o,int language) throws IOException {
	switch(language) {
	case RAW:
            return o.toString();
        case JAVA:
	    try{
		return produceList(o,0);
	    } catch(SyntaxError e) {
		throw new IOException(e.toString());
	    }
	case POP11:
	    StringWriter sw = new StringWriter(1024);
	    datafwrite(sw,o);
	    sw.flush();
	    return sw.toString();
	case CL:
	    try {
		return produceListCL(o);
	    } catch(CLSyntaxError e) {
		throw new IOException(e.toString());
	    }            
	case R:
	    try {
		return produceListR(o);
	    } catch(RSyntaxError e) {
		throw new IOException(e.toString());
	    }
	default:
	    if (strict) throw new IOException("Language code not defined: " + language);
	    System.err.print("Language code not defined: " + language);
	    return null;
	}
    }

    
    // subset of POP11 serialization in "datafile"
    // the parsing order in the if-statement is important
    @SuppressWarnings("unchecked")
    private static void datafwrite(Writer w,Object o) throws IOException {
	Stack stk = new Stack();
	stk.push(o);

	while (!stk.empty()) {
	    w.write(" ");
	    o = stk.pop();	
	    if (o instanceof Integer || o instanceof Float || o instanceof Double || o instanceof BigDecimal)
		w.write(o.toString().replace('E', 'e'));
	    else if (o instanceof Pop11Word) {
		// printing the structure takes up more space and is slower than
		// just printing the word but it ensures that words with non printing
		// characters are stored properly (eg -space-) and datafile control
		// words (e.g. zw) are not confused.
		byte[] wordbytes = (((Pop11Word)o).word).getBytes();
		w.write("zw ");
		w.write((new Integer(wordbytes.length)).toString());
		for(int i=0;i<wordbytes.length;i++) {
		    w.write(" ");
		    w.write((new Byte(wordbytes[i]).toString()));
		}	    
	    }
	    else if (o instanceof Pop11List) {
		ArrayList v = (ArrayList)o;
		w.write("zl "); 
		w.write((new Integer(v.size())).toString());
		for(int i = v.size()-1; i>=0; i--)		    
		    stk.push(v.get(i));
	    }	    
	    else if (o instanceof String) {
		byte[] stringbytes = ((String)o).getBytes();
		w.write("zs ");
		w.write((new Integer(stringbytes.length)).toString());
		for(int i=0;i<stringbytes.length;i++) {
		    w.write(" ");
		    w.write((new Byte(stringbytes[i])).toString());
		}
	    }
	    else if (o instanceof ArrayList) {
		ArrayList v = (ArrayList)o;
		w.write("zv "); 
		w.write((new Integer(v.size())).toString());
		for(int i = v.size()-1; i>=0; i--)		    
		    stk.push(v.get(i));
	    }
	    /* NOT IMPLEMENTED
	    else if (o instanceof Array) {		
		pr("za"); datafwrite(boundslist(x)); appdata(arrayArrayList(x),datafwrite);
	    }
	    */
	    /* NOT IMPLEMENTED
	       else if isref(x) then
	       pr("zr"); datafwrite(cont(x));
	    */
	    else if (o instanceof Boolean) {
		w.write("zb ");
		if (((Boolean)o).booleanValue())
		    w.write("true");
		else
		    w.write("false");
	    }
	    /* NOT IMPLEMENTED
	    else if isArrayListclass(x) then       ;;; user defined ArrayList
		spr("zu"); spr(dataword(x)); pr(datalength(x)); appdata(x,datafwrite);
	    */
	    else if (o instanceof Hashtable) {
		Hashtable h = (Hashtable)o;
		w.write("zh ");
		ArrayList ht = new ArrayList(h.size());
		int i = h.size()-1;
		// convert the hashtable to a list
		Enumeration ke = h.keys();
		Enumeration ee = h.elements();
		while (ke.hasMoreElements()) {
		    ArrayList item = new ArrayList(2);
		    item.add(ke.nextElement());
		    item.add(ee.nextElement());
		    ht.set(i,item);
		    i--;
		}
		// put the converted hashtable on the stack
		stk.push(ht);
		stk.push(new Integer(h.size()));
		stk.push("null");
		stk.push(new Boolean(true));
	    }
	    /* NOT IMPLEMENTED
	    elseif isclosure(x) then
 	        spr("zC"); pr(pdprops(pdpart(x))); pr(' ');
 	        datafwrite(datalist(x))
 	    elseif isprocedure(x) then
 	        spr("zP"); pr(pdprops(x));
            */
	    else {                
                // it is a structure we don't know so write the class name		
                w.write("zc ");
                Class co = o.getClass();
                // write the data word
                String key = co.getName();
                // but first, get rid of package names and the turn the rest into lower case
                // this is the naming convention in POPSWAGES
                w.write((key.substring(key.lastIndexOf('.')+1)).toLowerCase());
		// first try the serializer if it's there
		boolean tryserializer = false;
		// check if it has a serialization method defined, language will return its instances in a ArrayList
		try {
		    Method meth = co.getDeclaredMethod("toPop11",(Class[])null);
		    // Method meth = co.getDeclaredMethod("toPop11",null);
		    // found it, put each element of the return ArrayList on the stack in reverse order whatever it is
		    ArrayList pvec = (ArrayList)meth.invoke(o,(Object[])null);;
		    // ArrayList pvec = (ArrayList)meth.invoke(o,null);;
		    for(int i=pvec.size()-1;i>=0;i--) 
			stk.push(pvec.get(i));
		    // if we made it here it was successful
		    tryserializer = true;		    
		} catch (SecurityException e1) {
		    if (debug) System.err.println("Access to pop11 field serializer denied in " + o.getClass());
		} catch (IllegalAccessException e2) {
		    if (debug) System.err.println("Access to pop11 field serializer denied in " + o.getClass());
		} catch (NoSuchMethodException e3) {
		    if (debug) System.err.println("No pop11 field serializer defined in " + o.getClass());
		} catch (InvocationTargetException e4) {
		    if (debug) System.err.println("Cannot invoke field serializer defined in " + o.getClass());
		}
		// try the direct method if the serializer did not work
		if (!tryserializer) {
		    // try to get the declared fields
		    try {
			Field[] fs = co.getDeclaredFields();
			// got the fields, so put them on the stack, one by one--this will fail if they are not all Public
			for(int f=fs.length-1;f>=0;f--) {
			    // put the value of the field in object o on the stack
			    stk.push(fs[f].get(o));
			}
		    } catch (SecurityException e1) {
		    } catch (IllegalAccessException e2) {
		    } catch (IllegalArgumentException e3) {
		    } catch (NullPointerException e4) {
		    } catch (ExceptionInInitializerError e5) {
		    }
		}
            }
	}
    }

    // this sends a message to the server, waits for OK=0, and returns null if no problem occured
    // otherwise it will either throw an IOException if there was problem with the socket or it 
    // will return the error message packet from the receiver
    // the sender needs to take action if the receiver expected a different message
    @SuppressWarnings("unchecked")
    public static void sendMessage(int senderID,int mtype,Object data,Socket comm_sock,int language) throws IOException {	
	// use ArrayList, which is a super class to all specific lists...
	ArrayList v = new ArrayList(3);
	v.add(senderID);
	v.add(mtype);
	v.add(data);
	//	write(comm_sock,[%senderID,mtype,data%]);
	write(comm_sock,v,language);
        Object o = read(comm_sock,language);
        if (o instanceof Integer && ((Integer)o).intValue() != OK)
            throw new IOException("Received non-0 acknowledgement");
    }

    @SuppressWarnings("unchecked")
    public static void sendMessage(int senderID,int mtype,Object data,BufferedReader in,PrintWriter out,int language) throws IOException {	
        // use ArrayList, which is a super class to all specific lists...
	ArrayList v = new ArrayList(3);
	v.add(senderID);
	v.add(mtype);
	v.add(data);	
        //	write(comm_sock,[%senderID,mtype,data%]);        
	write(out,v,language);
        Object o = read(in,language,false);
        
        if (o instanceof Integer && ((language != CL &&((Integer)o).intValue() != OK )|| (language == CL && ((Integer)o).intValue() != 49)))
            throw new IOException("Received non-0 acknowledgement");
        
        ////while(!in.ready());
        //int ack = in.read();
        // MS: this is a hack since I don't know yet how to make CL send 0 or 1 through the socket...'
        //if (ack == NOTOK || (language == CL && ack != 49))
            //throw new IOException("Received NOTOK acknowledgement");
        /*
        //MS: only need to read a character now for acknowledgement
        System.out.println("=======");
        Object o = read(in,language);
        System.out.println(o);
        if (o instanceof Integer && ((Integer)o).intValue() != OK)
            throw new IOException("Received non-0 acknowledgement");
        */
    }
    
    // receives a message and returns it, throws an IO Exception if there was an unrecoverable problem
    public static ArrayList receiveMessage(Socket comm_sock,int language) throws IOException {
	ArrayList message;
	try {
            message = (ArrayList)read(comm_sock,language);
            write(comm_sock,OK,language);
            return message;
        } catch(ClassCastException e) {
            write(comm_sock,NOTOK,language);
            return null;
        }
    }

    public static ArrayList receiveMessage(BufferedReader in,PrintWriter out,int language) throws IOException {
        ArrayList message;
	try {
            Object o = read(in,language);
            message = (ArrayList)o;
            write(out,OK,language);
            return message;
        } catch(ClassCastException e) {
            System.err.println("---------> " + e);
            write(out,NOTOK,language);
            return null;
        }
    }
    
    // waits for a message of a particular kind, if a message of another kind is received 
    // it writes a packet with the specific packet request
    public static ArrayList waitForMessage(int typeofmessage,Socket comm_sock) throws IOException {
	return waitForMessage(typeofmessage,comm_sock,POP11);
    }

    public static ArrayList waitForMessage(int typeofmessage,Socket comm_sock,int language) throws IOException {
	//wait for input or return if the device is closed
	for(;;) {
	    ArrayList message = receiveMessage(comm_sock,language); 
	    if (message.get(2) instanceof Integer && ((Integer)message.get(2)) == typeofmessage) {
		write(comm_sock,OK,language);
                return message;
            }
            else
		write(comm_sock,NOTOK,language);
	}
    }
    

    public static void main(String[] args) {
	/*
	try {
 	    System.out.println(parseExpressionCL("(this is 0.9 `(1 ,\"2\"))"));
	    System.out.println(produceListCL(parseExpressionCL("(this is 0.9 `(1,\"2\"))")));
	} catch(Exception e) {
	    System.out.println("Caught: " + e);
	}
	*/

	/*
	 class testclass {
	    public Integer a = 0;
	    public Integer b = 0;
	    
	    public String toString() {
		return a + " " + b;
	    }
	}
	*/

	// test the list parser
	/*
	String start = "[[5 00:00:00 7.59][1 test 'string']]";
	ArrayList v = (ArrayList)Pop11.parseExpression(start);
	String r = produceList(v);
	System.out.println(r + "    " + r.equals(start));	
	*/
	/*
	try {
	    produceList(new File("parsetestout"),parseExpression(new File("parsetestin")));
	} catch (IOException e1) {
	} catch (Pop11SyntaxError e2) {}
	*/

	// test the serialization
	
	//testclass t;

	/*
	try {	    
	    Object o = read(new File("otest"));
	    //	    o = read(new File("otest"));

	    if (o == null)
		System.out.println("NULL");
	    else
		System.out.println(o);
	    write(new File("testout"),o);
	} catch (Exception e) {System.out.println("Caught: " + e);}
	
	*/
	// test socket connection to pop11
		
	try {
	    System.out.println("STARTING");
	    ServerSocket serverSocket = new ServerSocket(10000);
	    System.out.println("LISTENING ON 10000...");
	    while (true) {	    
		Socket comm_sock = serverSocket.accept();
		System.out.println("Client connecting..");
                BufferedReader in = new BufferedReader(new InputStreamReader(comm_sock.getInputStream()));
                PrintWriter out = new PrintWriter(comm_sock.getOutputStream(),false);
                //System.out.println(receiveMessage(in,out,R));
                //sendMessage(0,1,new Pop11List(),in,out,R);
		while (true) {
			System.out.println("Reading...");
		    System.out.println(in.readLine());
		    out.write("0\n");	
		    out.flush();
		    out.write("list(0,3,list(c(\"compilehere\",\"x<-999\")))");
		    		    out.flush();	
		    System.out.println("wroteit");
		}
                /*
                Object m;
                do {
                    System.out.println("Waiting...");
                    m = receiveMessage(0,in,out);
                    System.out.println("Received " + m);
                    if (!(m instanceof ArrayList)) {
                        System.err.println("CCYC was not a list, but a");
                        System.err.println(m.getClass());
                    }
                } while (!m.equals("DONE"));
                System.out.println("Received " + m);		
		comm_sock.close();
                 */
	    }
	} catch (IOException e) {
	    System.err.println("IOError: " + e);
	}
	
        /*
	    ArrayList l = new ArrayList(2);
    ArrayList m = new ArrayList(2);
    m.add(new Word("initfile"));
    m.add("testfile");
    l.add(m);
    ArrayList m2 = new ArrayList(2);
    m2.add(new Word("statsfile"));
    m2.add("testfile2");
    l.add(m2);
    try {
	System.out.println(produceListR(l));
    } catch(Exception e) {System.out.println(e);}
         */
	/*
	try {
	    ServerSocket serverSocket = new ServerSocket(10000);
	    while (true) {	    
		Socket comm_sock = serverSocket.accept();
                do {
                    System.out.println("Waiting...");
		    Object o = read(comm_sock,CL);
                    System.out.println("Received " + o);
                    System.out.println("Returning message...");
		    write(comm_sock,o,CL);
                } while (true);
	    }
	} catch (IOException e) {
	    System.err.println("IOError: " + e);
	}
	*/
    }
}
                                            comlink/Pop11List.java                                                                              0000664 0000764 0000764 00000001017 10621413146 015406  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Common Lisp list representation
 * 
 * Last modified: 05-12-07
 * 
 ********************************************************************/

package comlink;

// convenience class for pop11 lists
import java.util.ArrayList;
import java.io.Serializable;

public class Pop11List<E> extends ArrayList<E> {
    public Pop11List(int l) {
	super(l);
    }
    public Pop11List() {
        super();
    }
}
 
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 comlink/Pop11SyntaxError.java                                                                       0000664 0000764 0000764 00000000604 10544550066 017003  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Common Lisp syntax error
 * 
 * Last modified: 12-28-06
 * 
 ********************************************************************/

package comlink;

public class Pop11SyntaxError extends SyntaxError {
    public Pop11SyntaxError(String s) {
	super(s);
    }
}
                                                                                                                            comlink/Pop11Word.java                                                                              0000664 0000764 0000764 00000000646 10621413146 015415  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Pop11 word representation
 * 
 * Last modified: 12-28-06
 * 
 ********************************************************************/

package comlink;

import java.io.Serializable;

public class Pop11Word extends Word implements Serializable {
    public Pop11Word(String s) {
	super(s);
    }
}
                                                                                          comlink/rclient.R                                                                                   0000664 0000764 0000764 00000017774 10636567506 014633  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               #####################################################################
#
# SWAGES 1.1
#
# (c) by Matthias Scheutz <mscheutz@nd.edu>
#
# R Client
#
# Last modified: 06-18-07
#
#####################################################################

# Socket used for communication with server
comm_sock = FALSE

# by default the program runs in client mode, to stop this, pass
# either a command line argument, or call the simulation with a
# particular function
clientID = FALSE

# Number of attempts to connect to the server before giving up
connection_attempts = 50

# Waiting before a connection is attempted in sec.
waitforconnection = 10

# Number of attempts to receive a message
receive_attempts = 3

# default for communciation with the server
# this will be overwritten by experiment setup file
servername = "127.0.0.1" 

# "The port on the server used for connections"
serverport = 10009 

# for recording the output of the R analysis
saveSTATSFILE = FALSE
statsout = FALSE

# this will hold result files from model runs, etc. that the client might need
resultfiles = FALSE

# for logging standard output is connected to logger file, otherwise to /dev/null
logging = FALSE

# a seed for repeating an analysis that depends on random numbers
ranseed = 0

#for debugging: print out lots of comments
verbose = FALSE

# message types
PREQ = 0
SINT = 1 
SCNT = 2
SPAR = 3
CPAR = 4
DONE = 5
SSAV = 6
CCYC = 7
PCYC = 8
PSAV = 9
SPLT = 10
ALLD = 11;
UCID = 12;

OK = "1"
NOTOK = "-1"

# this dummy function needs to be overwritten with code during simulation setup
# (e.g., the actr6 code defines a run function that will override it)
run <- function(stats) {
  print("These are the parameters passed to 'run': ")
  print(stats)
}

# INCOMPLETE
# parses the parameters that the R client can deal with
parseparameters <- function (params) {
  for (n in 1:length(params)) {
    p <- params[[n]]
    key <- p[[1]]
    val <- p[[2]]
    if (key == "initfile") {
      if (verbose) print(paste("INITFILE:", val))
      source(val)
    }
    else if (key == "compilehere") {
      if (verbose) print(paste("EVAL:", val))
      eval(parse(text = val))
    }
    else if (key == "statsfile") {
      if (verbose) print(paste("STATSFILE:", val))
      saveSTATSFILE <<- val
    }
    else if (key == "resultfiles") {
      if (verbose) print(paste("RESULTSFILES:", val))
      resultfiles <<- val
    }

# NEED TO IMPLEMENT THIS RIGHT STILL
    else if (key == "ranseed") {
      if (verbose) print(paste("RANSEED:", val))
      ranseed <<- val
    }
    else if (key == "setglobal") {
      # check if the argument is a string, then it needs to be quoted seperately...
      if (is.character(p[[3]])) {
        eval(parse(text=paste(val,"<<- \"",p[[3]],"\"")))
      }
      else {
        eval(parse(text=paste(val,"<<- ",p[[3]])))
      }
    }
    # ignore unknown keys
    else {
      if (verbose) print(paste("Unknown key:", key))
    }
  }
}

# can separate two messages, will not work for more than two, but that
# case should never happen
last = ""
read_line <- function () {
  message = ""
  if (last != "") {
    #print(paste("LAST:",last))
    message <- last
    last <<- ""
  }
  else {
    nonewline = TRUE
    while (nonewline) {
      while (message == "") {
        message <- read.socket(comm_sock)
      }
      m = strsplit(message, "\n")[[1]]
      # check if there are was a newline in it, there was none if the strings are the same...
      if (length(m) > 1) {
        # there was a difference, so check if the newline was only at the end of the first string
        # then the second message was incomplete and we need to read more
        if (message == paste(m[1],"\n",m[2],sep="")) {
          # there were two strings, need to figure out if there was a newline at the end of the second
          # otherwise we have to finish reading until we get one
          # this will not work if the new read creates another \n...  SHOULD NEVER HAPPEN given the protocol
          last <<- paste(m[2],read_line(),sep="")        
        }
        # 2nd message was complete, so just set last to the 2nd message
        else {
          last <<- m[2]
        }          
        # return in any case the first part of the message with the \n
        message <- m[1]
      }
      # if there was no \n in the message, it is incomplete, need to read more
      else if (paste(m,"\n",sep="") != message) {
        message <- paste(m,read_line(),sep="")
      }
      # if the message was not OK or NOTOK, then we still need to read until we hit the \n
      #else if ((m != OK) && (m != NOTOK)) {
      #  message <- paste(message,read_line(),sep="")                
      #}
      # only one message and the message was complete
      else {
        message <- m
      }
      # we are done, return the message
      nonewline <- FALSE
    }
  }
  return(message)
}

# sends a messages
send_message <- function (senderID, mtype, data) {
  write.socket(comm_sock, paste("(\"", senderID, "\" ", mtype, " ", data,")\n", sep = ""))
  message <- read_line()
#  print(paste("GOT MESSAGE BACK...",message))
  if (message == OK) {
    return(TRUE)
  }
  else {
    return(FALSE)
  }
}

# receives a message
receive_message <- function () {
  message <- read_line()
  if (message == "") {
    close.socket(comm_sock)
    FALSE
  }
  else {
    write.socket(comm_sock, OK)
    write.socket(comm_sock, "\n")
    return(eval(parse(text=message)))
  }
}

# waits for a message of a particular type
wait_for_message <- function (typeofmessage) {
  message <- read_line()
  while (message != "") {
    message <- eval(parse(text = message))
    if (message[[2]] == typeofmessage) {
      write.socket(comm_sock, OK)
      write.socket(comm_sock, "\n")
      return(message)
    }
    else {
      message <- read_line()
    }
  }
  FALSE
}

# keeps sending a message and re-opening the socket on failure
keep_sending_message <- function (mID, mtype, mdata) {
  for (n in 1:connection_attempts) {
    if (send_message(mID, mtype, mdata))
      return(TRUE)
    if (verbose) print(paste("SHOULD NEVER GET HERE...", comm_sock))
    close.socket(comm_sock)
    comm_sock <<- make.socket(servername, port = serverport)
    system(paste("sleep", 100 * waitforconnection))
  }
  FALSE  
}

# dummy reset function to reset R
reset <- function () {
}

# the main entry point called by SWAGES
runclient <- function (params) {
  if (is.list(params)) {
    servername <- params[[1]]
    serverport <- params[[2]]
    clientID <- params[[3]]
  }
  
  # NOTE: R already writes the output to a file in command mode...
  if (logging) {
    zz <- file("/tmp/rclientout", open = "wt")
    sink(zz)
    sink(zz, type = "message")
  }

  while (TRUE) {
    simparametermessage = FALSE
    while (!simparametermessage) {
      # print(servername)
      # print(serverport)
      comm_sock <<- make.socket(servername, port = serverport)
      on.exit(close.socket(comm_sock))
      # print("Sending PREQ")
      keep_sending_message(clientID, PREQ, FALSE)
      # print("waiting for SPAR")
      simparametermessage <- wait_for_message(SPAR)
      # print("received SPAR...")
      # print(paste("SIMPARAM:",simparametermessage))

      if (length(simparametermessage) > 1) {
        parseparameters(simparametermessage[[3]][[1]])
        break
      }
    }

    # open the stats file if supplied
    if (is.character(saveSTATSFILE)) statsout <- file(saveSTATSFILE, open = "wt")
    
    if (verbose) print("Analysis started")
    run(statsout)
    if (verbose) print("Analysis finished")

    # if the statsfile was open, close it and relay the information
    if (is.character(saveSTATSFILE)) {
      close(statsout)
      keep_sending_message(clientID, DONE, paste("(",0," ",file.info(saveSTATSFILE)$size,")"))
    }
    else {
      keep_sending_message(clientID, DONE, paste("(",0," ",0,")"))
    }
    
    clientID <- (wait_for_message(UCID))[[3]]
    # if we did not get a new ID, then finish
    if (is.list(clientID)) {
      # close the socket
      close.socket(comm_sock)
      quit(save="no")
    }
    # otherwise the VM will be re-used, so reset the simulation
    else {
      reset()
    }    
  }
}
    comlink/RSymbol.java                                                                                0000664 0000764 0000764 00000000622 10621413146 015242  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Common Lisp symbol representation
 * 
 * Last modified: 05-12-07
 * 
 ********************************************************************/

package comlink;

import java.io.Serializable;

public class RSymbol extends Word {
    public RSymbol(String s) {
	super(s);
    }
}
                                                                                                              comlink/RSyntaxError.java                                                                           0000664 0000764 0000764 00000000562 10544764365 016320  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * R syntax error
 * 
 * Last modified: 12-28-06
 * 
 ********************************************************************/

package comlink;

public class RSyntaxError extends SyntaxError {
    public RSyntaxError(String s) {
	super(s);
    }
}
                                                                                                                                              comlink/swclient.p                                                                                  0000775 0000764 0000764 00000076466 10763075100 015050  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 *
 * SWAGES 1.1
 *
 * (c) by Matthias Scheutz <mscheutz@nd.edu>
 *
 * Pop11 Parallel Client
 *
 * Last modified: 12-28-06
 *
 *********************************************************************/

discout('/tmp/swages') ->> cucharout -> cucharerr;

uses unix_sockets;
lconstant this_dir = sys_fname_path(popfilename);

;;; ------------------- load libraries --------------------------
;;; load the simulator and all required files
compile(this_dir dir_>< 'simworld.p');
;;; additional pop11 files for network communication
compile(this_dir dir_>< 'datasockets.p');

;;; ------------------- globals for client stuff  --------------------------
global vars
    ;;; socket used for communication with server
    comm_sock,

    ;;; by default the program runs in client mode, to stop this, pass
    ;;; either a command line argument, or call the simulation with a
    ;;; particular function
    clientID = false,
    connection_attempts = 50,   ;;; attempts to connect to the server before giving up
    waitforconnection = 10,     ;;;(in sec.)
    receive_attempts = 3,       ;;; number of attempts to receive a message

    ;;; default for communciation with the server
    ;;; this will be overwritten by experiment setup file
    servername = '127.0.0.1',
    serverport = 10002,

    ;;; for non-cluster mode:
    ;;; used to check whether there is a user on the console
    checkMIGRATION = false,     ;;; whether we should perform checks on the host
    maxtimeconsoleuser = 24000, ;;; run for little less than 5 min. of CPU time

    ;;; this will save the state of the simulation
    saveSTATE = false,          ;;; saveSTATE * checkINTERVAL = frequency at which simstate is saved
    timercount = 0,             ;;; variable containing the number of times the migration check has been performed
    IDLETIME = 30,		;;; how much idle time console user needs to accumulate before we'll start a job on his machine
    KEEPOUTPUT = false,

    proxyLOW = false,
    proxyHIGH = false,
    PARALLEL = false,
;

;;; message types
lconstant 
     PREQ = 0,
     SINT = 1, 
     SCNT = 2,
     SPAR = 3,
     CPAR = 4,
     DONE = 5,
     SSAV = 6,
     CCYC = 7,
     PCYC = 8,
     PSAV = 9,
     SPLT = 10;

;;; for debugging: print out lots of comments
lconstant verbose = false;

;;; parallel SWAGES stuff
global vars proxy_objects = [],
	    nonproxy_objects = [],
	    normal_objects = [],
	    killme, interactions, final_objects, sim_run_agent_stackloc,
	    some_agent_ran,
	    ;

define :mixin proxy;
    slot proxy_update_cycle == 0;
    slot proxy_update_list == [ sim_x sim_y ];
    slot cpu_total == 0; ;;; Total CPU time for agent
    slot cpu_elapsed == [% 0 %]; ;;; List of CPU times for agent
    slot cpu_sense_total == 0; ;;; Total sensing CPU time for agent
    slot cpu_sense_elapsed == 0; ;;; Sensing CPU time for current cycle
    slot cpu_action_total == 0; ;;; Total action CPU time for agent
    slot cpu_action_elapsed == 0; ;;; Action CPU time for current cycle
    slot cpu_overall == 0; ;;; CPU time for the current process
    slot real_total == 0; ;;; Total real time for agent
    slot real_elapsed == [% 0 %]; ;;; List of real times for agent
enddefine;

define :method proxy_update(entity:proxy, updatelist);
    lvars sname, sval;
    for sname sval in proxy_update_list(entity), updatelist do
	sval -> valof(sname)(entity);
    endfor;
enddefine;

define par_sim_scheduler(objects, lim); enddefine;

;;; this will try to send a message and if it does not succeed, it will reopen a new socket
;;; uses the globals: comm_sock, servername, and serverport
define keep_sending_message(mID,mtype,mdata);
    repeat connection_attempts times
    	returnif(send_message(mID,mtype,mdata,comm_sock))(true);
    	;;; close socket and reestablish connection to server and send ID, so the server
    	sys_socket(`i`, `S`, false) -> comm_sock;
    	[%servername, serverport%] -> sys_socket_peername(comm_sock);
	syssleep(waitforconnection*100);
    endrepeat;
    sysexit();
    return(false);
enddefine;

define saveit(imagename);
    ;;; Suppress warning messages
    dlocal cucharerr = discout('/dev/null');
    return(syssave(imagename));
enddefine;

;;; this will save the state of the simulation and notify the server
define migrate(level,safety);
    if saveit(imagename) then
/*
	;;; first check whether the CID is still the same, this can be seen from the image name
	;;; 2nd or 3rd argument
	lvars us = locchar_back(`_`,length(poparglist(2)),poparglist(2)),
	     dot = locchar_back(`.`,length(poparglist(2)),poparglist(2)),
	     imID = consword(substring(us,dot-us,poparglist(2)));

	;;; if they are not identical, the server must have changed the ID for this client, so use the new one
	unless consword(imID) = clientID then
	    imID -> clientID;
	endunless;
*/
        ;;; the clientID is passed as an argument
	poparglist(1) -> clientID;
	discout('/tmp/swages_' >< clientID) ->> cucharout -> cucharerr;

	lvars tobecompiled = false;
	lconstant verbose = true;
	;;; try until successful
    	while not(tobecompiled) do
    	    ;;; establish connection to server and send ID, so the server
	    sys_socket(`i`, `S`, false) -> comm_sock;
	    [%servername, serverport%] -> sys_socket_peername(comm_sock);
	
    	    ;;; contact server and request the simulation parameters
	    until keep_sending_message(clientID,SCNT,[]) do 
		if verbose then npr('keep_sending_message failed for client ' >< clientID); endif;
	    enduntil;
    	    if verbose then npr(clientID >< ' Sent SCNT to server, waiting for CPAR...') endif;
	
    	    ;;; now get the simulation parameters
    	    wait_for_message(clientID,CPAR,comm_sock) -> tobecompiled;
    	endwhile;
        compile(stringin(tobecompiled(3)));
	if proxyLOW then
	    ;;; for loop--go through nonproxy list and place in proper list
	    lvars i = 1, tmpobj, newnonproxy = [], newproxy = [];
	    for tmpobj in nonproxy_objects do
		if i >= proxyLOW and i <= proxyHIGH then
		    tmpobj :: newnonproxy -> newnonproxy;
		else
		    tmpobj :: newproxy -> newproxy;
		endif;
		i + 1 -> i;
	    endfor;
	    rev(newnonproxy) -> nonproxy_objects;
	    ;;; Note that this does not preserve the order of proxy objects
	    rev(newproxy) -> proxy_objects;
	    false -> proxyLOW;
	endif;
	if verbose then npr(clientID >< ' Received CPAR, continuing simulation..') endif;
    else
        ;;; check whether we saved it for safety reasons, then we don't need to inform the server
	unless safety then
    	    npr('Client '>< clientID >< ' attempting to migrate...');	
	    saveSTATSFILE =>
	    until keep_sending_message(clientID,SINT,[%level,sysfilesize(imagename)%]) do enduntil;
	    if verbose then npr('Sent SINT to server, quitting simulation') endif;
    	    npr('Client ' ><  clientID >< ' gone...');	
            ;;; Clean up the psv files in /tmp, unless we're coming back to this
	    ;;; machine	   
	    unless level = 3 then
/*		if sys_file_exists(imagename) then
		    ;;; delete it if it exists
		    sysobey('/bin/rm', [%'/bin/rm',imagename%]);
		endif;
        */
		if sys_file_exists(imagename><'-') then
		    sysobey('/bin/rm', [%'/bin/rm',imagename><'-'%]);
		endif;
                if sys_file_exists(imagename >< '--') then
    	            sysobey('/bin/rm', [%'/bin/rm',imagename><'--'%]);
                endif;
                if sys_file_exists(imagename >< '---') then
    	            sysobey('/bin/rm', [%'/bin/rm',imagename><'---'%]);
                endif;
	    endunless;
	    sysexit(1);
	;;; otherwise let the server know that we are still around and that we saved state, so it can grab the image
	else
	    ;;; level contains the cycle number
	    until keep_sending_message(clientID,SSAV,[%level,sysfilesize(imagename),false%]) do enduntil;
	endunless;
	unless KEEPOUTPUT then
	    discout('/tmp/swages') ->> cucharout -> cucharerr;
	    if sys_file_exists('/tmp/swages_' >< clientID) then
		sysobey('/bin/rm', [%'/bin/rm','/tmp/swages_' >< clientID%]);
	    endif;
	endunless;
    endif;
enddefine;

;;; check whether the time t is within the interval (s,e)
define within_time_interval(t,s,e);
    lvars (th,tm,ts) = sys_parse_string(t,`:`,strnumber),
	 (sh,sm,ss) = sys_parse_string(s,`:`,strnumber),
	 (eh,em,es) = sys_parse_string(e,`:`,strnumber),
	 c = th*3600 + tm*60 + ts;
    (sh*3600 + sm*60 + ss < c) and (c < eh*3600 + em*60 + es)
enddefine;

;;; NOTE: this function overwrites the save_simstate in simworld.p  !!!
;;; this performs all kinds of periodic checks of the host on which the simulation is
;;; running according to the following check levels (if the conditions are met, the simulation
;;; will migrate):
;;; 1 - any other user logged on
;;; 2 - a console user looged on
;;; 3 - a console user logged on and "maxtimeconsoleuser" was exceeded, in sec.
;;; 4 - the cpu time of the process dropped below "mincputime"
;;; all of this can be specified for certain intervals of the day
;;; the argument is a list of lists each of which is of the form
;;;	[level] sets runlevel
;;;	[level param] if level is 4, param is maximum allowable load
;;;		      
;;;	[level starttime endtime]
;;; regardless of the above the state of the simulation can also be saved at regular intervals

;;; TODO: here we could also check the socket and see if the server request any information from us,
;;; e.g., the current number of sim_cycles, etc. and send it across
define save_simstate(cycle);
    dlocal pop_asts_enabled;
    if useTIMER then
    	false -> pop_asts_enabled;
    else
    	;;; increase the timer count
    	timercount + 1 -> timercount;
    endif;

    lvars alreadymigrated = false;
    ;;; check if any user is logged on
    if checkMIGRATION then
	lvars item, currenttime = substring(12,8,sysdaytime());
	for item in checkMIGRATION do
	    lvars level = item(1),
		 timeok = if length(item) = 3 then
		              within_time_interval(currenttime,item(2),item(3))
		          elseif length(item) = 2 then
			      item(2)
			  else true endif;
            ;;; check if anybody is on
    	    if level == 1 and timeok then
	    	if line_repeater(pipein('./test_user',[],false),255)()/='false' then
	    	    migrate(1,false);
		    true->alreadymigrated;
		    quitloop(1);
	    	endif;
   	    ;;; check if a console user is on
    	    elseif level == 2  and timeok then
       	    	if line_repeater(pipein('./test_console',[],false),255)()/='false' then
    	    	    migrate(2,false);
		    true->alreadymigrated;
		    quitloop(1);
	    	endif;
	    ;;; check if a console user is on and the overall CPU time of the pop process
 	    ;;; exceeded the "maxtimeconsoleuser"
            elseif level == 3  and timeok then
	    	if line_repeater(pipein('./test_console',[],false),255)()/='false' and
               		(systime() > maxtimeconsoleuser) then
               		;;;(systime() * 100 > maxtimeconsoleuser) then
    	    	    migrate(3,false);
		    true->alreadymigrated;
		    quitloop(1);
	    	endif;	
	    ;;; check if the percentage of CPU this process gets is less a certain percentage
 	    elseif level == 4 then
		if strnumber(line_repeater(pipein('./test_cpu',[],false),255)()) < timeok then
    	    	    migrate(4,false);
		    true->alreadymigrated;
		    quitloop(1);
	    	endif;	
    	    elseif level == 5  and timeok then
		lvars idleresp,idleentry,idletime;
       	    	line_repeater(pipein('./test_console_idle',[],false),255)() -> idleresp;
		if idleresp = termin then
		    migrate(5,false);
		    true->alreadymigrated;
		    quitloop(1);
		endif;
       	    	if idleresp /= 'false' then
		    sysparse_string(idleresp) -> idleresp;
		    1 -> idleentry;
		    0 -> idletime;
		    if null(idleresp) then
			;;; No idle time, better get off the machine
			migrate(5,false);
			true->alreadymigrated;
			quitloop(1);
		    endif;
		    while length(idleresp) > idleentry and isnumber(idleresp(idleentry)) do
			if idleresp(idleentry + 1) = 'days' or 
			   idleresp(idleentry + 1) = 'day' then
			    idletime + (24*60*idleresp(idleentry)) -> idletime;
			elseif idleresp(idleentry + 1) = 'hours' or
			       idleresp(idleentry + 1) = 'hour' then
			    idletime + (60*idleresp(idleentry)) -> idletime;
			elseif idleresp(idleentry + 1) = 'minutes' or
			       idleresp(idleentry + 1) = 'minute' then
			    idletime + (idleresp(idleentry)) -> idletime;
			endif;
			idleentry + 2 -> idleentry;
		    endwhile;
		    if idletime < IDLETIME then
			;;; Idle time less than threshold, get off machine
			migrate(5,false);
			true->alreadymigrated;
			quitloop(1);
		    endif;
	    	endif;
	    ;;; Migrate if I'm too close to 5 min CPU limit, regardless of user
            elseif level == 6  and timeok then
	    	if systime() > maxtimeconsoleuser then
    	    	    migrate(3,false);
		    true->alreadymigrated;
		    quitloop(1);
	    	endif;	
	    ;;; check if the percentage of CPU this process gets is less a certain percentage
	    elseif level == -1 then
		;;; after split
    	    endif;
	endfor;
    endif;
    ;;; check if we need to save the state for safety reasons, then we will continue here...
    if isnumber(saveSTATE) and not(alreadymigrated) and (timercount rem saveSTATE = 0) then
	;;; save state without migrating, pass on the cycle number to server if necessary
	migrate(0,cycle);	
    ;;; unless we have already migrated and notified the server, produce a "current cycle" (CCYC) update message if required
    elseif not(alreadymigrated) then
	if PARALLEL then
	    lvars updatelist, offer, pobject, npobject, message, xlist, ylist,
		  deadp = [],
		  ;
	    /*
	    [%  for npobject in nonproxy_objects do
		    sim_cycle_number -> proxy_update_cycle(npobject);
		    [% float_code_bytes(sim_x(npobject) * 1.0) %] -> xlist;
		    [% float_code_bytes(sim_y(npobject) * 1.0) %] -> ylist;
		    [% sim_name(npobject), cycle, "sim_x", xlist, "sim_y", ylist %]
		    ;;;[% sim_name(npobject), sim_cycle_number, npobject %]
		endfor %] -> offer;
	    */
	    [] -> offer;
	    until keep_sending_message(clientID,PCYC, [% cycle, length(nonproxy_objects), offer, [] %]) do enduntil;   
	    receive_message(clientID, comm_sock) -> message;
	    message(3) -> updatelist;
	    for pobject in updatelist do
		lvars i = 3;
		lvars AID = valof(pobject(1));
		;;;pobject(3) -> idval(identof(pobject(1)));
		pobject(2) -> proxy_update_cycle(AID);
		while i <= length(pobject) do
		    ;;; PWS: later we can use the proxy class update
		    ;;; function, but since the message 
		    explode(pobject(i + 1)) -> float_code_bytes() -> valof(pobject(i))(AID);
		    i + 2 -> i;
		endwhile;
		;;; PWS: This is a clumsy attempt to detect death...
		if sim_x(AID) = 1000000 then
		    dies_basic_agent(AID, "eaten");
		    AID :: deadp -> deadp;
		endif;
		/*
		*/
	    endfor;
	    if deadp /= [] then
		[% for pobject in proxy_objects do unless lmember(pobject, deadp) then pobject endunless endfor %] -> proxy_objects;
	    endif;
	    ;;; PWS: need to check for SPLT
	    if message(2) = SPLT then
		npr('Received SPLT');
		migrate(-1, false);
	    endif;
	else
	    until keep_sending_message(clientID,CCYC,[%cycle%]) do enduntil;   
	endif;
    endif;
    ;;; if the timer is used, set it
    if useTIMER then
        checkINTERVAL -> sys_timer(save_simstate);
    	true -> pop_asts_enabled;
    endif;
enddefine;

;;; replace the item following a key in an arbitrary list structure
define replacevalofkey(l,key,newitem);
    if null(l) then
        []
    elseif hd(l) == key then
        [% hd(l), newitem %] <> replacevalofkey(tl(tl(l)),key,newitem)
    elseif islist(hd(l)) then
        conspair(replacevalofkey(hd(l),key,newitem),
                 replacevalofkey(tl(l),key,newitem))
    else
        conspair(hd(l),replacevalofkey(tl(l),key,newitem))
    endif;
enddefine;

;;; returns the list of values with matching key, false if there are none
define getvalsfromkey(l,k);
    lvars x;
    for x in l do
        if hd(x) = k then
            return(tl(x))
        endif;
    endfor;
    false
enddefine;

;;; this function is the main entry point for the client
;;; it gets all the simulation parameters from the host
define runclient(params);
    ;;; make yourself independent of the calling shell, the father returns immediately, only the child continues
    if sys_fork(true) then 
	return;	
    endif;

    ;;;if verbose then npr('runclient executing') endif;
    ;;; get server, port, clientID, imagename (including the path), the checking frequency, the save state info, the local scratch
    ;;; info, and the ranseed
    unless null(params) then
        explode(params) -> (servername,serverport,clientID);
    endunless;
    discout('/tmp/swages_' >< clientID) ->> cucharout -> cucharerr;

    lvars simparammessage = false, tmpparseuser;
    lconstant verbose = false;

    ;;; this keeps reconnecting until the simparam messages is received
    ;;; MS: quoted out    while not(simparammessage) do
    ;;; establish connection to server and send ID, so the server
    sys_socket(`i`, `S`, false) -> comm_sock;
    [%servername, serverport%] -> sys_socket_peername(comm_sock);
    
    do
	;;; contact server and request the simulation parameters
        until keep_sending_message(clientID,PREQ,[]) do 
    	    if verbose then npr('keep_sending_message failed for client ' >< clientID); endif;
        enduntil;
    	if verbose then npr(clientID >< ' Sent PREQ to server, waiting for SPAR...') endif;
	sys_real_time() -> lastCHECK;
    	;;; now get the simulation parameters

    	wait_for_message(clientID,SPAR,comm_sock) -> simparammessage;
	;;; MS: quoted out   endwhile;	

    	if verbose then npr(clientID >< ' Received simparams from server: ' >< simparammessage(3)) endif;
	
    	;;; check if the state needs to be saved and/or the checkMIGRATION criteria are still met
    	;;;save_simstate(0);
	
    	;;; ignore server keywords in the parameter lists
    	true -> ignoreUNKNOWNKEYWORD;
    	parseuserPARAMS -> tmpparseuser;
    	procedure(kw,params,tmpproc);
	    lvars k = hd(kw);
	    if k == "parallel" then
	    	;;; PWS: this is where we're supposed to alter params
	    	;;; [% sys_parse_string(hd(entity), `_`) %]
	    	lvars entity;
	    	true -> PARALLEL;
	    	;;; Forces save image after first cycle
	    	if checkINTERVAL then
		    - checkINTERVAL - 1 -> lastCHECK;
	    	endif;
	    	par_sim_scheduler -> sim_scheduler;
	    	[%	for entity in params(2) do
		    	    lvars eparse = [% sys_parse_string(hd(entity), `_`) %],
			  	 rulestring,
			  	 classstring,
			  	 ;
		    	    if eparse(length(eparse)) = 'agent' then
				'vars proxy_' >< hd(entity) >< '_rulesystem = ' >< hd(entity) >< '_rulesystem;' -> rulestring;
				compile(stringin(rulestring));
				'define :class proxy_' >< hd(entity) >< '; is proxy, ' >< hd(entity) >< '; enddefine;' -> classstring;
				compile(stringin(classstring));
				('proxy_' >< hd(entity)) :: tl(entity)
		    	    else
				entity
		    	    endif;
			endfor %] -> params(2);
	    elseif tmpproc then
	    	tmpproc(kw);
	    endif;
    	endprocedure(%tmpparseuser%) -> parseuserPARAMS;
	
    	;;;run simulation on the simparam, which are the in the message body
    	simulate(simparammessage(3));
	
    	;;; tell the server that the client has finished, include the final cycle number
    	until keep_sending_message(clientID,DONE,[%current_cycle,sysfilesize(saveSTATSFILE)%]) do enduntil;
	
    	;;; clean up only backup copies, as the client may still be copying the last image in case something
    	;;; went wrong with it 
    	if sys_file_exists(imagename >< '-') then
    	    sysobey('/bin/rm', [%'/bin/rm',imagename><'-'%]);
    	endif;
    	if sys_file_exists(imagename >< '--') then
    	    sysobey('/bin/rm', [%'/bin/rm',imagename><'--'%]);
    	endif;
    	if sys_file_exists(imagename >< '---') then
    	    sysobey('/bin/rm', [%'/bin/rm',imagename><'---'%]);
    	endif;
    	
    	;;; for reuse of client
    	wait_for_message(clientID,UCID,comm_sock)(3) -> clientID;
    	;;; if we got a new ID, the VM will be re-used, so reset the simulation
    	if not(null(clientID)) then
	    ;;; reset the simulation
	    reset-simulation();
    	endif;
    while clientID;

    unless KEEPOUTPUT then
	discout('/tmp/swages') ->> cucharout -> cucharerr;
	if sys_file_exists('/tmp/swages_' >< clientID) then
	    ;;;sysobey('/bin/rm', [%'/bin/rm','/tmp/swages_' >< clientID%]);
	endif;
    endunless;
    if verbose then npr('All data was transmitted successfully, client ' >< clientID >< ' is shutting down'); endif;
enddefine;

define lconstant procedure sim_stack_check(object, len, name, cycle);
    lvars object, len, name, cycle, inc, mess, vec = {};
    stacklength() - len -> inc;
    returnif(inc == 0);

    if inc fi_> 0 then
	consvector(inc) -> vec;
	'Stack increased by ',
    else
	'Stack decreased by '
    endif sys_>< abs(inc) sys_>< ' items in cycle ' sys_>< cycle -> mess;
    ;;; Reduce call stack before calling mishap
    chain(mess, ['In' ^name, ^object %explode(vec)%], mishap)
enddefine;

define lconstant prb_STOPAGENT(rule_instance, action);
	lvars rest = fast_back(action);
	if ispair(rest) then rest==> endif;
	unless prb_actions_run == 0 then true -> some_agent_ran endunless;
	exitto(sim_run_agent_stackloc);
enddefine;

prb_STOPAGENT -> prb_action_type("STOPAGENT");

define lconstant prb_STOPAGENTIF(rule_instance, action);
	lvars rest = fast_back(action);
	if ispair(rest) then
		if recursive_valof(fast_front(rest)) then
			if ispair(fast_back(rest)) then fast_back(rest) ==> endif;
			unless prb_actions_run == 0 then true -> some_agent_ran endunless;
			exitto(sim_run_agent_stackloc);
		endif
	else
		mishap('MISSING ITEM AFTER STOPAGENTIF', [^action])
	endif;
enddefine;

define par_sim_scheduler(objects, lim);
    lvars proxy_tmp, objects, object, speed, lim, messages, messagelist = [];
    lvars tmptime;
    
    ;;; clear any previously saved objects.
    [] -> final_objects;

    ;;; make the list of objects globally accessible, to methods, etc.
    dlocal pop_pr_places = (`0` << 16) || 16;

    dlocal
	some_agent_ran,

	popmatchvars,
	sim_objects = objects,
	sim_myself ,	    ;;; used so that rules can access self
	sim_cycle_number = 0,	;;; incremented below
	sim_object_delete_list = [],
	sim_object_add_list = [],
	;;; supppress printing of rulesystem information
	prb_noprint_keys = sim_noprint_keys,
	sim_stopping_scheduler = false,
	;

    
    for proxy_tmp in objects do
	if isproxy(proxy_tmp) then
	    proxy_tmp :: nonproxy_objects -> nonproxy_objects;
	    unless isdeclared(sim_name(proxy_tmp)) then
		ident_declare(sim_name(proxy_tmp),0,0);
	    endunless;
	    proxy_tmp -> idval(identof(sim_name(proxy_tmp)));
	else
	    proxy_tmp :: normal_objects -> normal_objects;
	endif;
    endfor;
    rev(nonproxy_objects) -> nonproxy_objects;
    rev(normal_objects) -> normal_objects;

    ;;; First ensure that rulesystems are all analysed and rulesets stored
    ;;; in databases, etc.

    procedure();    ;;; exitto(sim_scheduler), will exit this
      lvars len = stacklength();

        ;;; make sure all agents have been setup before anything
	;;; starts
      applist(sim_objects, sim_setup);

      repeat
	lvars pobject, npobject, pobjectlist, updatelist = [], rmlist = [],
	      offer, request, message, npobjectlist, deadnp = [], deadp = [],
	      npupdatelist = [],
	      ;
	;;; check whether to abort
	quitif(sim_cycle_number == lim);	;;; never true if lim = false

	;;; PWS: Here I'm going through the proxy agents to see which need
	;;; updating; working on a copy of the list

	
	lvars newpobjectlist = copylist(proxy_objects);	
	;;;lvars pobjectlist = copylist(proxy_objects);	
	fast_for npobject in nonproxy_objects do
	    lvars ints = interactions(npobject), ints2, npupdate = false;

	    if killme(npobject) then
		npobject :: deadnp -> deadnp;
		1000000 -> sim_x(npobject);
		1000000 -> sim_y(npobject);
		nextloop;
	    endif;
 	    newpobjectlist -> pobjectlist;
	    [] -> newpobjectlist;
	    [% fast_for pobject in pobjectlist do
		lvars pdist = sim_cycle_number - proxy_update_cycle(pobject), idist, idist2;
		
		if pdist > 0 then
		    lvars cname = class_name(datakey(pobject));
		    unless ints and (ints matches ![== ^cname ?idist ==]) then
			max_range(npobject) -> idist;
		    endunless;
		    ;;;npr('it\'s been ' >< pdist >< ' cycles');
		    pdist * maxspeed(pobject) -> pdist;
		    ;;;npr('could\'ve gone ' >< pdist >< ' units');
		    sim_distance(npobject, pobject) - pdist -> pdist;

		    ;;;npr('so it could be ' >< pdist >< ' close to me');
		    if abs(pdist) < idist then
			;;;npr('proxy ' >< sim_name(pobject) >< ' may be in range of nonproxy ' >< sim_name(npobject));
			pobject :: updatelist -> updatelist;
			true -> npupdate;
		    else
			lvars cname2;
		    	interactions(pobject) -> ints2;
		    	class_name(datakey(npobject)) -> cname2;
		    	unless ints2 and (ints2 matches ![== ^cname2 ?idist2 ==]) then
			    max_range(pobject) -> idist2;
		    	endunless;
			if abs(pdist) < idist2 then
			    ;;;npr('nonproxy ' >< sim_name(npobject) >< ' may be in range of proxy ' >< sim_name(pobject));
			    pobject :: updatelist -> updatelist;
			    true -> npupdate;
			endif;
		    endif;
		else
		    pobject
		endif;
	    endfast_for %] -> newpobjectlist;
	endfast_for;

	;;; PWS: now create the message
	[%  for pobject in updatelist do
		sim_name(pobject)
	    endfor %] -> request;
	/*
	[%  for pobject in updatelist do
		[% sim_name(pobject), "sim_x", "sim_y" %] 
	    endfor %] -> request;
	*/
	if request /= [] or deadnp /= [] then
	    lvars xlist, ylist, deaths = false, updateprint = [];
	    ;;; make this a vector for faster access later
	    {%  fast_for npobject in nonproxy_objects do
		    sim_cycle_number -> proxy_update_cycle(npobject);
		    {% float_code_bytes(sim_x(npobject) * 1.0) %} -> xlist;
		    {% float_code_bytes(sim_y(npobject) * 1.0) %} -> ylist;
		    {% sim_name(npobject), if killme(npobject) then 1000000 else sim_cycle_number endif, "sim_x", xlist, "sim_y", ylist %}
		    ;;;[% sim_name(npobject), sim_cycle_number, npobject %]
		endfast_for %} -> offer;
	    ;;;'offer:' =>
	    ;;;offer ==>
	    keep_sending_message(clientID,PCYC,[% sim_cycle_number, length(nonproxy_objects), offer, request %]) -> ;
	    receive_message(clientID, comm_sock) -> message;
	    message(3) -> updatelist;
	    fast_for pobject in updatelist do
		lvars i = 3;
		lvars AID = valof(pobject(1));
		pobject(2) -> proxy_update_cycle(AID);
		while i <= length(pobject) do
		    ;;; PWS: later we can use the proxy class update
		    ;;; function, but since the message 
		    explode(pobject(i + 1)) -> float_code_bytes() -> valof(pobject(i))(AID);
		    i + 2 -> i;
		endwhile;
		;;; PWS: This is a clumsy attempt to detect death...
		if sim_x(AID) = 1000000 then
		    dies_basic_agent(AID, "eaten");
		    true -> deaths;
		    AID :: deadp -> deadp;
		endif;
		[% sim_name(AID), proxy_update_cycle(AID), "sim_x", sim_x(AID), "sim_y", sim_y(AID) %] :: updateprint -> updateprint;
	    endfast_for;
	    ;;; PWS: I need to do this here because the deaths might come
	    ;;; before the cycle, but objects are not removed until after
	    ;;; the cycle.  The return from SPLT should be OK, though,
	    ;;; because it happens at the end of the cycle.
	    if deaths then
		sim_edit_object_list(sim_objects, sim_cycle_number) -> sim_objects;
	    endif;
	    ;;; PWS: Need to check here for SPLT
	    if message(2) = SPLT then
		migrate(-1, false);
	    endif;
	    ;;;npr('updates:');
	    ;;;rev(updateprint) ==>
	endif;
	
	;;; this should be made faster too, take them out above
	if deadnp /= [] then
	    [% fast_for npobject in nonproxy_objects do unless lmember(npobject, deadnp) then npobject endunless endfast_for %] -> nonproxy_objects;
	endif;
	if deadp /= [] then
	    [% fast_for pobject in proxy_objects do unless lmember(pobject, deadp) then pobject endunless endfast_for %] -> proxy_objects;
	endif;
	
	sim_cycle_number fi_+ 1 -> sim_cycle_number;
	;;; Allow user-definable setup, e.g. for graphics
	sim_setup_scheduler(sim_objects, sim_cycle_number);

	false -> some_agent_ran;    ;;; may be set true in sim_run_agent

	;;; go through all objects running their rules, then do
	;;; post-processing to update world
	;;; PWS: only going through non-proxy objects
	fast_for object in normal_objects do

	    ;;; XXX should do interval check here?
	    ;;; Must check if agent needs to be set up, in case it is
	    ;;; new or has been given a new rulesystem
	    unless sim_setup_done(object) then sim_setup(object) endunless;
	    object -> sim_myself;
            [] -> popmatchvars;
	    ;;; NOW LET THE AGENT DO ITS INTERNAL STUFF
	    ;;; PWS: sending all objects, could limit for performance
	    sim_run_agent(object, sim_objects);
	    sim_stack_check(object, len, sim_run_agent, sim_cycle_number);
	endfast_for;
	fast_for object in nonproxy_objects do

	    ;;; XXX should do interval check here?
	    ;;; Must check if agent needs to be set up, in case it is
	    ;;; new or has been given a new rulesystem
	    unless sim_setup_done(object) then sim_setup(object) endunless;
	    object -> sim_myself;
            [] -> popmatchvars;
	    ;;; NOW LET THE AGENT DO ITS INTERNAL STUFF
	    ;;; PWS: sending all objects, could limit for performance
	    timediff() -> tmptime;
	    sim_run_agent(object, sim_objects);
	    timediff() -> cpu_sense_elapsed(object);
	    cpu_sense_elapsed(object) + cpu_sense_total(object) -> cpu_sense_total(object);
	    sim_stack_check(object, len, sim_run_agent, sim_cycle_number);

	endfast_for;
	
	
;;;	if some_agent_ran then
	    ;;; now distribute messages and perform actions to update world
	    ;;; PWS: only going through non-proxy objects
	    fast_for object in normal_objects do;
		object -> sim_myself;
		sim_do_actions(object, sim_objects, sim_cycle_number);
	    endfast_for;

	    fast_for object in nonproxy_objects do;
		object -> sim_myself;
		timediff() -> tmptime;
		sim_do_actions(object, sim_objects, sim_cycle_number);
		timediff() -> cpu_action_elapsed(object);
		cpu_action_elapsed(object) + cpu_action_total(object) -> cpu_action_total(object);
		cpu_sense_total(object) + cpu_action_total(object) -> cpu_total(object);
		(cpu_sense_elapsed(object) + cpu_action_elapsed(object)) :: cpu_elapsed(object) -> 
		    cpu_elapsed(object);
		systime() -> cpu_overall(object);
	    endfast_for;
/*
	else
	    ;;; no rules were fired in any object
	    no_objects_runnable_trace(normal_objects <> nonproxy_objects, sim_cycle_number)
	endif;
*/
	sim_scheduler_pausing_trace(normal_objects <> nonproxy_objects, sim_cycle_number);

	;;; This can add new objects or delete old ones
	sim_edit_object_list(sim_objects, sim_cycle_number) -> sim_objects;

	;;; This can be used for updating a connected simulation, etc.
	sim_post_cycle_actions(normal_objects <> nonproxy_objects, sim_cycle_number);

	;;; Moved after call to sim_post_cycle_actions at suggestion of BSL
	[] ->> sim_object_delete_list -> sim_object_add_list;

	;;; Added 8 Oct 2000
        if sim_stopping_scheduler then 
	    sim_stop_scheduler(); 
	endif;

      endrepeat
    endprocedure();

    sim_scheduler_finished(sim_objects, sim_cycle_number);
    lvars xlist, ylist, npobject, offer, message;
    [%  fast_for npobject in nonproxy_objects do
	    npr('FINAL: ' >< sim_name(npobject) >< ' sim_x ' >< sim_x(npobject) >< ' simy ' >< sim_y(npobject));
	    sim_cycle_number -> proxy_update_cycle(npobject);
	    [% float_code_bytes(sim_x(npobject) * 1.0) %] -> xlist;
	    [% float_code_bytes(sim_y(npobject) * 1.0) %] -> ylist;
	    [% sim_name(npobject), sim_cycle_number, "sim_x", xlist , "sim_y", ylist %]
	    ;;;[% sim_name(npobject), sim_cycle_number, npobject %]
	endfast_for %] -> offer;
    keep_sending_message(clientID,PCYC,[% sim_cycle_number, length(nonproxy_objects), offer, [] %]) -> ;
    receive_message(clientID, comm_sock) -> message;
    npr('Quitting!');

    sim_objects -> final_objects;

enddefine;

                                                                                                                                                                                                          comlink/SyntaxError.java                                                                            0000664 0000764 0000764 00000000554 10544550116 016162  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Syntax error
 * 
 * Last modified: 12-28-06
 * 
 ********************************************************************/

package comlink;

public class SyntaxError extends Exception {
    public SyntaxError(String s) {
	super(s);
    }
}
                                                                                                                                                    comlink/Word.java                                                                                   0000664 0000764 0000764 00000001435 10621412735 014574  0                                                                                                    ustar   mscheutz                        mscheutz                                                                                                                                                                                                               /*********************************************************************
 * 
 * SWAGES 1.1
 * 
 * (c) by Matthias Scheutz
 * 
 * Common word/symbol representation
 * 
 * Last modified: 05-12-07
 * 
 ********************************************************************/

package comlink;

import java.io.Serializable;

public class Word implements Comparable<String>, Serializable  {
    public String word = null;
    public Object binding = null;
    public boolean backquote = false;

    public Word(String s) {
	word = s;
    }

    public Word(byte[] s) {
	word = new String(s);
    }

    public String toString() {
	return word;
    }
    
    public boolean equals(Object o) {
        return word.equals(o);
    }
    
    public int compareTo(String s) {
	return word.compareTo(s);
    }
}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   